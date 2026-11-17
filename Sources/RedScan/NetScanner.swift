import Foundation
import AppKit
import UniformTypeIdentifiers

@MainActor
final class NetScanner: ObservableObject {
    @Published var devices: [String: Device] = [:]
    @Published var network: NetworkInfo?
    @Published var isScanning = false
    @Published var phase = "Bereit"
    @Published var progress: Double = 0
    @Published var customTarget = ""
    @Published var publicIP: String?
    @Published var loadingPublicIP = false
    @Published var lastScan: Date?
    @Published var busyDevices: Set<String> = []
    @Published var scanDuration: TimeInterval?
    @Published var arpBlocked = false

    func openLocalNetworkSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Ersatz, wenn ARP fehlt: AirPlay `deviceid` oder RAOP-Name "AABBCCDDEEFF@Name".
    static func macFromServices(_ services: [BonjourService]) -> String? {
        for s in services {
            if let id = s.txt["deviceid"], id.firstMatch(#"^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$"#) != nil { return id.uppercased() }
            if s.type.hasPrefix("_raop"), let hex = s.name.firstMatch(#"^([0-9A-Fa-f]{12})@"#)?[1] {
                return stride(from: 0, to: 12, by: 2).map { i -> String in
                    let a = hex.index(hex.startIndex, offsetBy: i)
                    return String(hex[a..<hex.index(a, offsetBy: 2)])
                }.joined(separator: ":").uppercased()
            }
        }
        return nil
    }

    @Published var toast: String?

    let vendorCount = VendorDB.shared.count
    let history: HistoryStore
    private var task: Task<Void, Never>?
    private let bonjour = BonjourScanner()

    init(history: HistoryStore) {
        self.history = history
        network = NetworkDetector.detect()
    }

    // MARK: - Wake-on-LAN

    func wake(mac: String, name: String) {
        var targets: [String] = []
        if let net = network ?? NetworkDetector.detect(), let b = WakeOnLAN.broadcast(of: net) { targets.append(b) }
        let ok = WakeOnLAN.wake(mac: mac, broadcasts: targets)
        showToast(ok ? "Magic Packet an „\(name)“ gesendet (\(mac))" : "Ungültige MAC-Adresse: \(mac)")
    }

    func showToast(_ text: String) {
        toast = text
        Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            if toast == text { toast = nil }
        }
    }

    /// Ist ein Gerät aus dem Verlauf gerade online (im aktuellen Scan)?
    func isOnline(_ k: KnownDevice) -> Bool {
        devices.values.contains { HistoryStore.key(for: $0) == k.key }
    }

    var sortedDevices: [Device] { devices.values.sorted { $0.ipSortKey < $1.ipSortKey } }
    var totalOpenPorts: Int { devices.values.reduce(0) { $0 + $1.openPorts.count } }
    var totalServices: Int { devices.values.reduce(0) { $0 + $1.services.count } }

    // MARK: - Steuerung

    func start() {
        guard !isScanning else { return }
        let previous = task
        // Ein abgebrochener Scan muss erst vollständig enden, bevor der neue startet.
        task = Task {
            previous?.cancel()
            await previous?.value
            await runScan()
        }
    }

    func cancel() {
        task?.cancel()
        bonjour.stop()
        isScanning = false
        phase = "Abgebrochen"
    }

    func refreshNetwork() { network = NetworkDetector.detect(customCIDR: customTarget) }

    func fetchPublicIP() {
        loadingPublicIP = true
        Task {
            publicIP = await Web.publicIP() ?? "nicht erreichbar"
            loadingPublicIP = false
        }
    }

    // MARK: - Geräte-Updates

    private func update(_ ip: String, source: String? = nil, _ change: (inout Device) -> Void) {
        var d = devices[ip] ?? Device(ip: ip)
        change(&d)
        if let source { d.discoveredBy.insert(source) }
        if d.mac == nil, let m = Self.macFromServices(d.services) { d.mac = m; d.discoveredBy.insert("MAC via Bonjour") }
        if let mac = d.mac {
            if d.vendor == nil { d.vendor = VendorDB.shared.lookup(mac) }
            d.randomizedMAC = VendorDB.isRandomized(mac)
        }
        if d.model == nil { d.model = Classifier.appleModel(from: d.services) }
        d.kind = Classifier.classify(d)
        devices[ip] = d
    }

    private func inScope(_ ip: String) -> Bool {
        guard let net = network, let v = IPv4.toUInt32(ip), let first = net.hosts.first.flatMap(IPv4.toUInt32), let last = net.hosts.last.flatMap(IPv4.toUInt32) else { return false }
        return v >= first && v <= last
    }

    // MARK: - Scan-Ablauf

    private func runScan() async {
        isScanning = true
        defer { isScanning = false; lastScan = Date() }
        let started = Date()
        progress = 0
        phase = "Netzwerk wird erkannt …"
        guard let net = await offMain({ [customTarget] in NetworkDetector.detect(customCIDR: customTarget) }) else {
            phase = "Kein aktives Netzwerk gefunden"
            return
        }
        network = net
        devices = [:]

        update(net.ip, source: "Lokal") { d in
            d.isSelf = true; d.mac = net.mac; d.latencyMs = 0
        }

        // 0. Geräte, die der Mac schon kennt, sofort anzeigen
        await applyARP(net)

        // 1. Ping-Sweep (schneller ICMP-Sweep, Rückfall auf ping-Prozesse)
        let hosts = net.hosts.filter { $0 != net.ip }
        phase = "Ping-Sweep über \(hosts.count.formatted()) Adressen …"
        let sweeper = ICMPSweeper()
        async let sweepOK = offMain { sweeper.run(hosts, rate: 2000, wait: 2.0) }
        var ticks = 0
        while !sweeper.finished {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { sweeper.cancel() }
            applyPings(sweeper.drain(), net)
            progress = 0.35 * Double(sweeper.sent) / Double(max(hosts.count, 1))
            ticks += 1
            if ticks % 8 == 0 { await applyARP(net) } // Ping-blockierende Geräte live einblenden
        }
        let ok = await sweepOK
        applyPings(sweeper.drain(), net)
        if !ok && hosts.count <= 2048 { await processPingSweep(hosts, net) }
        if Task.isCancelled { return }

        // 2. ARP-Tabelle – findet auch Geräte, die Ping blockieren
        phase = "ARP-Tabelle wird ausgewertet …"
        await applyARP(net)
        progress = 0.38

        // 3. Namen & Dienste (parallel)
        phase = "Bonjour, UPnP, NetBIOS & DNS werden abgefragt …"
        let ips = Array(devices.keys)
        async let ssdp = offMain { SSDP.discover(timeout: 3.5) }
        async let netbios = offMain { NetBIOS.query(ips, timeout: 2.0) }
        async let mdns = offMain { MDNS.reverse(ips, timeout: 2.5) }
        async let rdns = offMain { ReverseDNS.lookup(ips, timeout: 4) }
        let bonjourFound = await bonjour.browse(duration: 7)
        if Task.isCancelled { return }

        for f in bonjourFound where inScope(f.ip) || f.ip == net.ip {
            update(f.ip, source: "Bonjour") { d in
                if !d.services.contains(where: { $0.id == f.service.id }) { d.services.append(f.service) }
                if d.mdnsName == nil, let h = f.service.hostName { d.mdnsName = h.trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
            }
        }
        for (ip, r) in await netbios {
            update(ip, source: "NetBIOS") { d in
                d.netbiosName = r.name; d.netbiosGroup = r.group
                if d.mac == nil { d.mac = r.mac }
            }
        }
        for (ip, name) in await mdns where devices[ip] != nil {
            update(ip, source: "mDNS") { $0.mdnsName = name.trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
        }
        for (ip, name) in await rdns where devices[ip] != nil {
            update(ip, source: "DNS") { $0.hostname = name }
        }
        progress = 0.5

        // UPnP-Beschreibungen laden
        let ssdpResponses = await ssdp
        var seenLocations = Set<String>()
        phase = "UPnP-Gerätebeschreibungen werden geladen …"
        await withTaskGroup(of: (String, UPnPInfo).self) { group in
            for r in ssdpResponses where inScope(r.ip) || r.ip == net.ip {
                guard let loc = r.headers["LOCATION"], seenLocations.insert(loc).inserted else { continue }
                let server = r.headers["SERVER"]
                group.addTask { (r.ip, await SSDP.describe(location: loc, server: server)) }
            }
            for await (ip, info) in group {
                update(ip, source: "UPnP") { d in
                    if !d.upnp.contains(where: { $0.location == info.location }) { d.upnp.append(info) }
                }
            }
        }
        await applyARP(net) // Neue Geräte aus Bonjour/UPnP bekommen ihre MAC
        progress = 0.55
        if Task.isCancelled { return }

        // 4. Port-Scan
        let targets = sortedDevices.map(\.ip)
        phase = "Port-Scan (\(Ports.common.count) Ports pro Gerät) …"
        var scanned = 0
        await withTaskGroup(of: (String, [Int]).self) { group in
            var it = targets.makeIterator()
            for _ in 0..<16 {
                guard let ip = it.next() else { break }
                group.addTask { (ip, await offMain { Ports.scan(ip: ip, ports: Ports.common) }) }
            }
            for await (ip, open) in group {
                if Task.isCancelled { group.cancelAll(); break }
                scanned += 1
                progress = 0.55 + 0.25 * Double(scanned) / Double(max(targets.count, 1))
                update(ip) { d in
                    d.openPorts = open.map { OpenPort(port: $0, service: Ports.label($0)) }
                    d.portsScanned = true
                }
                if let n = it.next() { group.addTask { (n, await offMain { Ports.scan(ip: n, ports: Ports.common) }) } }
            }
        }
        if Task.isCancelled { return }

        // 5. Banner & Web-Infos
        phase = "Banner, Webseiten & Zertifikate werden gelesen …"
        await enrich(targets)
        progress = 1
        scanDuration = Date().timeIntervalSince(started)
        history.record(devices: sortedDevices, network: net, duration: scanDuration)
        let newCount = history.newInLastScan.count
        phase = "Fertig – \(devices.count) Geräte gefunden" + (newCount > 0 ? ", \(newCount) neu" : "")

        // Debug: `--dump <pfad>` schreibt das Ergebnis als JSON (für Tests ohne UI)
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--dump"), i + 1 < args.count {
            let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]; enc.dateEncodingStrategy = .iso8601
            try? enc.encode(sortedDevices).write(to: URL(fileURLWithPath: args[i + 1]))
        }
    }

    private func applyPings(_ results: [(String, PingResult)], _ net: NetworkInfo) {
        for (ip, r) in results {
            update(ip, source: "Ping") { d in
                d.latencyMs = r.time
                if r.ttl > 0 { d.ttl = r.ttl }
                d.isGateway = ip == net.gateway
            }
        }
    }

    /// Alter Weg: ein ping-Prozess pro Adresse (nur falls kein ICMP-Socket verfügbar ist).
    private func processPingSweep(_ hosts: [String], _ net: NetworkInfo) async {
        var done = 0
        await withTaskGroup(of: (String, PingResult?).self) { group in
            var it = hosts.makeIterator()
            for _ in 0..<64 {
                guard let h = it.next() else { break }
                group.addTask { (h, await offMain { Ping.ping(h) }) }
            }
            for await (ip, r) in group {
                if Task.isCancelled { group.cancelAll(); break }
                done += 1
                progress = 0.35 * Double(done) / Double(max(hosts.count, 1))
                if let r { applyPings([(ip, r)], net) }
                if let n = it.next() { group.addTask { (n, await offMain { Ping.ping(n) }) } }
            }
        }
    }

    private func applyARP(_ net: NetworkInfo) async {
        let entries = await offMain { ARP.table() }
        // Ohne "Lokales Netzwerk"-Freigabe blendet macOS die ARP-Tabelle komplett aus.
        arpBlocked = entries.isEmpty
        for e in entries where e.iface == net.interface && (inScope(e.ip) || e.ip == net.ip) {
            update(e.ip, source: "ARP") { d in
                d.mac = e.mac
                d.isGateway = e.ip == net.gateway
            }
        }
    }

    /// Liest Banner (SSH, FTP …), HTTP-Titel/Server und TLS-Zertifikate der offenen Ports.
    private func enrich(_ ips: [String]) async {
        await withTaskGroup(of: (String, Int, String?, HTTPInfo?).self) { group in
            for ip in ips {
                guard let d = devices[ip] else { continue }
                for p in d.openPorts.map(\.port) {
                    if Ports.httpsPorts.contains(p) {
                        group.addTask { (ip, p, nil, await Web.fetch(ip: ip, port: p, tls: true)) }
                    } else if Ports.httpPorts.contains(p) {
                        group.addTask { (ip, p, nil, await Web.fetch(ip: ip, port: p, tls: false)) }
                    } else if Ports.bannerPorts.contains(p) || !Ports.names.keys.contains(p) {
                        group.addTask { (ip, p, await offMain { Ports.banner(ip: ip, port: p) }, nil) }
                    }
                }
            }
            for await (ip, port, banner, http) in group {
                update(ip) { d in
                    if let banner, let i = d.openPorts.firstIndex(where: { $0.port == port }) { d.openPorts[i].banner = banner }
                    if let http {
                        d.http.removeAll { $0.port == port }
                        d.http.append(http)
                        d.http.sort { $0.port < $1.port }
                        if let i = d.openPorts.firstIndex(where: { $0.port == port }) {
                            d.openPorts[i].banner = [http.server, http.title.map { "„\($0)“" }].compactMap { $0 }.joined(separator: " · ").nilIfEmpty
                        }
                    }
                }
            }
        }
    }

    // MARK: - Einzelgerät

    func deepScan(_ ip: String) {
        guard !busyDevices.contains(ip) else { return }
        busyDevices.insert(ip)
        Task {
            let open = await offMain { Ports.scan(ip: ip, ports: Ports.deep, timeoutMs: 1000) }
            update(ip) { d in
                d.openPorts = open.map { p in d.openPorts.first { $0.port == p } ?? OpenPort(port: p, service: Ports.label(p)) }
                d.portsScanned = true
                d.deepScanned = true
            }
            await enrich([ip])
            busyDevices.remove(ip)
        }
    }

    func repingDevice(_ ip: String) {
        Task {
            if let r = await offMain({ Ping.ping(ip) }) {
                update(ip) { $0.latencyMs = r.time; $0.ttl = r.ttl }
            }
        }
    }

    // MARK: - Export

    func exportJSON() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd_HH-mm"
        panel.nameFieldStringValue = "RedScan_\(f.string(from: Date())).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(sortedDevices) { try? data.write(to: url) }
    }

    func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "RedScan.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        func esc(_ s: String?) -> String { "\"\((s ?? "").replacingOccurrences(of: "\"", with: "\"\""))\"" }
        var rows = ["IP;Name;Typ;MAC;Hersteller;Hostname;mDNS;NetBIOS;OS;Latenz ms;Offene Ports;Dienste"]
        for d in sortedDevices {
            rows.append([d.ip, d.displayName, d.kind.label, d.mac, d.vendor, d.hostname, d.mdnsName, d.netbiosName, d.osGuess,
                         d.latencyMs.map { String(format: "%.1f", $0) },
                         d.openPorts.map { "\($0.port)" }.joined(separator: " "),
                         d.services.map(\.typeLabel).joined(separator: ", ")].map(esc).joined(separator: ";"))
        }
        try? rows.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

