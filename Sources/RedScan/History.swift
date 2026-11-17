import Foundation

/// Ein Gerät, das bei irgendeinem Scan schon einmal gesehen wurde.
struct KnownDevice: Codable, Identifiable, Hashable {
    var id: String { key }
    let key: String            // MAC (bevorzugt) oder "ip:<adresse>"
    var mac: String?
    var lastIP: String
    var ips: [String]
    var name: String
    var kind: DeviceKind
    var vendor: String?
    var network: String
    var openPorts: [Int]
    var firstSeen: Date
    var lastSeen: Date
    var seenCount: Int
}

/// Ein abgeschlossener Scan.
struct ScanRecord: Codable, Identifiable, Hashable {
    var id = UUID()
    let date: Date
    let network: String
    let ssid: String?
    let duration: Double?
    let deviceKeys: [String]
    let newKeys: [String]
    let goneKeys: [String]
}

@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var known: [String: KnownDevice] = [:]
    @Published private(set) var scans: [ScanRecord] = []
    /// Geräte, die beim letzten Scan zum ersten Mal auftauchten.
    @Published private(set) var newInLastScan: Set<String> = []

    private struct File: Codable { var known: [String: KnownDevice]; var scans: [ScanRecord] }
    private let url: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("RedScan", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("history.json")
        load()
    }

    static func key(for d: Device) -> String { d.mac ?? "ip:\(d.ip)" }

    var sortedKnown: [KnownDevice] { known.values.sorted { $0.lastSeen > $1.lastSeen } }

    func known(for d: Device) -> KnownDevice? { known[Self.key(for: d)] }

    /// Übernimmt das Ergebnis eines abgeschlossenen Scans in den Verlauf.
    func record(devices: [Device], network: NetworkInfo, duration: Double?) {
        let now = Date()
        var keys: [String] = []
        var new: [String] = []
        for d in devices {
            let k = Self.key(for: d)
            keys.append(k)
            // Früher nur per IP bekannt, jetzt mit MAC → alten Eintrag übernehmen
            if d.mac != nil, known[k] == nil, var old = known["ip:\(d.ip)"] {
                known["ip:\(d.ip)"] = nil
                old = KnownDevice(key: k, mac: d.mac, lastIP: old.lastIP, ips: old.ips, name: old.name, kind: old.kind, vendor: old.vendor,
                                  network: old.network, openPorts: old.openPorts, firstSeen: old.firstSeen, lastSeen: old.lastSeen, seenCount: old.seenCount)
                known[k] = old
                for i in scans.indices {
                    let s = scans[i]
                    func fix(_ a: [String]) -> [String] { a.map { $0 == "ip:\(d.ip)" ? k : $0 } }
                    scans[i] = ScanRecord(id: s.id, date: s.date, network: s.network, ssid: s.ssid, duration: s.duration,
                                          deviceKeys: fix(s.deviceKeys), newKeys: fix(s.newKeys), goneKeys: fix(s.goneKeys))
                }
            }
            if var kd = known[k] {
                kd.lastIP = d.ip
                if !kd.ips.contains(d.ip) { kd.ips.append(d.ip) }
                kd.name = d.displayName; kd.kind = d.kind
                kd.vendor = d.vendor ?? kd.vendor
                kd.mac = d.mac ?? kd.mac
                kd.network = network.cidr
                kd.openPorts = d.openPorts.map(\.port)
                kd.lastSeen = now
                kd.seenCount += 1
                known[k] = kd
            } else {
                new.append(k)
                known[k] = KnownDevice(key: k, mac: d.mac, lastIP: d.ip, ips: [d.ip], name: d.displayName, kind: d.kind,
                                       vendor: d.vendor, network: network.cidr, openPorts: d.openPorts.map(\.port),
                                       firstSeen: now, lastSeen: now, seenCount: 1)
            }
        }
        // "Verschwunden" = beim letzten Scan desselben Netzes da, jetzt nicht mehr
        let previous = scans.first { $0.network == network.cidr }
        let gone = previous.map { Set($0.deviceKeys).subtracting(keys).sorted() } ?? []
        // Beim allerersten Scan eines Netzes ist alles "neu" – das nicht als Neuheit markieren
        let firstScanOfNetwork = previous == nil
        newInLastScan = firstScanOfNetwork ? [] : Set(new)
        scans.insert(ScanRecord(date: now, network: network.cidr, ssid: network.ssid, duration: duration,
                                deviceKeys: keys, newKeys: firstScanOfNetwork ? [] : new, goneKeys: gone), at: 0)
        if scans.count > 200 { scans.removeLast(scans.count - 200) }
        save()
    }

    func remove(_ key: String) {
        known[key] = nil
        newInLastScan.remove(key)
        save()
    }

    func clear() {
        known = [:]; scans = []; newInLastScan = []
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        if let f = try? dec.decode(File.self, from: data) { known = f.known; scans = f.scans }
    }

    private func save() {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted]
        if let data = try? enc.encode(File(known: known, scans: scans)) { try? data.write(to: url, options: .atomic) }
    }
}

// MARK: - Wake-on-LAN

enum WakeOnLAN {
    /// Sendet das "Magic Packet" (6× 0xFF + 16× MAC) per UDP-Broadcast an Port 9 und 7.
    @discardableResult
    static func wake(mac: String, broadcasts: [String]) -> Bool {
        let hex = mac.replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: "")
        guard hex.count == 12 else { return false }
        var bytes: [UInt8] = []
        var i = hex.startIndex
        while i < hex.endIndex {
            let j = hex.index(i, offsetBy: 2)
            guard let b = UInt8(hex[i..<j], radix: 16) else { return false }
            bytes.append(b); i = j
        }
        var packet = [UInt8](repeating: 0xFF, count: 6)
        for _ in 0..<16 { packet += bytes }
        guard let sock = UDPSocket() else { return false }
        let targets = Array(Set(broadcasts + ["255.255.255.255"]))
        for t in targets {
            for port: UInt16 in [9, 7] {
                for _ in 0..<3 { sock.send(Data(packet), to: t, port: port) }
            }
        }
        return true
    }

    static func broadcast(of net: NetworkInfo) -> String? {
        guard let ip = IPv4.toUInt32(net.ip), let mask = IPv4.toUInt32(net.netmask) else { return nil }
        return IPv4.toString(ip | ~mask)
    }
}
