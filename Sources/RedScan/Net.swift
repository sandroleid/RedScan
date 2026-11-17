import Foundation
import Darwin

// MARK: - Hilfsfunktionen

/// Führt blockierende Arbeit auf einem GCD-Thread aus, ohne den Swift-Concurrency-Pool zu blockieren.
func offMain<T>(_ work: @escaping () -> T) async -> T {
    await withCheckedContinuation { cont in
        DispatchQueue.global(qos: .userInitiated).async { cont.resume(returning: work()) }
    }
}

enum Shell {
    static func run(_ path: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}

extension String {
    func firstMatch(_ pattern: String, options: NSRegularExpression.Options = []) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let ns = self as NSString
        guard let m = re.firstMatch(in: self, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0)) }
    }

    func allMatches(_ pattern: String) -> [[String]] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = self as NSString
        return re.matches(in: self, range: NSRange(location: 0, length: ns.length)).map { m in
            (0..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0)) }
        }
    }

    var printableCleaned: String {
        let scalars = unicodeScalars.map { s -> Character in
            (s.value >= 32 && s.value < 127) || (s.value > 160 && s.value != 0xFFFD) ? Character(s) : " "
        }
        return String(scalars).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}

extension Array {
    func chunked(_ size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}

enum IPv4 {
    static func toUInt32(_ s: String) -> UInt32? {
        var a = in_addr()
        guard inet_pton(AF_INET, s, &a) == 1 else { return nil }
        return UInt32(bigEndian: a.s_addr)
    }

    static func toString(_ v: UInt32) -> String {
        "\(v >> 24 & 0xff).\(v >> 16 & 0xff).\(v >> 8 & 0xff).\(v & 0xff)"
    }

    static func string(_ a: in_addr) -> String { toString(UInt32(bigEndian: a.s_addr)) }

    static func prefixLength(_ mask: UInt32) -> Int { mask.nonzeroBitCount }

    /// Liefert die Host-Adressen eines Netzes "a.b.c.d/n".
    static func hosts(cidr: String, limit: Int = 4096) -> [String]? {
        let parts = cidr.trimmingCharacters(in: .whitespaces).split(separator: "/")
        guard let base = toUInt32(String(parts[0])) else { return nil }
        let prefix = parts.count > 1 ? Int(parts[1]) ?? 32 : 32
        guard (16...32).contains(prefix) else { return nil }
        if prefix >= 31 { return [toString(base)] }
        let mask: UInt32 = prefix == 0 ? 0 : ~UInt32(0) << UInt32(32 - prefix)
        let net = base & mask
        let bcast = net | ~mask
        let count = Int(bcast - net - 1)
        guard count <= limit else { return nil }
        return (1...count).map { toString(net + UInt32($0)) }
    }
}

extension sockaddr_in {
    static func make(_ ip: String, _ port: UInt16) -> sockaddr_in {
        var a = sockaddr_in()
        a.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        a.sin_family = sa_family_t(AF_INET)
        a.sin_port = port.bigEndian
        inet_pton(AF_INET, ip, &a.sin_addr)
        return a
    }
}

func normalizeMAC(_ raw: String) -> String {
    raw.split(separator: ":").map { $0.count == 1 ? "0" + $0 : String($0) }.joined(separator: ":").uppercased()
}

/// Erhöht das Limit offener Dateien (nötig für parallele Port-Scans).
func raiseFileLimit() {
    var rl = rlimit()
    if getrlimit(RLIMIT_NOFILE, &rl) == 0 {
        rl.rlim_cur = min(rl.rlim_max, 8192)
        setrlimit(RLIMIT_NOFILE, &rl)
    }
}

// MARK: - UDP

final class UDPSocket {
    let fd: Int32

    init?(bindPort: UInt16 = 0) {
        fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return nil }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &on, socklen_t(MemoryLayout<Int32>.size))
        var ttl: UInt8 = 4
        setsockopt(fd, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, socklen_t(1))
        if bindPort != 0 {
            setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &on, socklen_t(MemoryLayout<Int32>.size))
            var addr = sockaddr_in.make("0.0.0.0", bindPort)
            _ = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
            }
        }
    }

    deinit { close(fd) }

    func send(_ data: Data, to ip: String, port: UInt16) {
        var addr = sockaddr_in.make(ip, port)
        data.withUnsafeBytes { buf in
            _ = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, buf.baseAddress, buf.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }

    func receive(for seconds: Double, handler: (String, [UInt8]) -> Void) {
        let deadline = Date().addingTimeInterval(seconds)
        var buf = [UInt8](repeating: 0, count: 65535)
        while true {
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { break }
            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let r = poll(&pfd, 1, Int32(remaining * 1000))
            if r < 0 && errno == EINTR { continue }
            if r <= 0 { break }
            var from = sockaddr_in()
            var len = socklen_t(MemoryLayout<sockaddr_in>.size)
            let n = withUnsafeMutablePointer(to: &from) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { recvfrom(fd, &buf, buf.count, 0, $0, &len) }
            }
            if n > 0 { handler(IPv4.string(from.sin_addr), Array(buf[0..<n])) }
        }
    }
}

// MARK: - Netzwerk-Erkennung

enum NetworkDetector {
    static func detect(customCIDR: String? = nil) -> NetworkInfo? {
        let route = Shell.run("/sbin/route", ["-n", "get", "default"])
        let gateway = route.firstMatch(#"gateway:\s*([\d.]+)"#)?[1]
        let routeIf = route.firstMatch(#"interface:\s*(\S+)"#)?[1]

        var v4: [String: (ip: UInt32, mask: UInt32)] = [:]
        var macs: [String: String] = [:]
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0 else { return nil }
        defer { freeifaddrs(ifap) }
        var ptr = ifap
        while let p = ptr {
            let ifa = p.pointee
            let name = String(cString: ifa.ifa_name)
            if let sa = ifa.ifa_addr {
                if sa.pointee.sa_family == UInt8(AF_INET), let nm = ifa.ifa_netmask {
                    let ip = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
                    let mask = nm.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
                    if v4[name] == nil { v4[name] = (ip, mask) }
                } else if sa.pointee.sa_family == UInt8(AF_LINK) {
                    sa.withMemoryRebound(to: sockaddr_dl.self, capacity: 1) { dl in
                        let d = dl.pointee
                        guard d.sdl_alen == 6, let off = MemoryLayout<sockaddr_dl>.offset(of: \sockaddr_dl.sdl_data) else { return }
                        let base = UnsafeRawPointer(dl).advanced(by: off + Int(d.sdl_nlen))
                        let bytes = (0..<6).map { base.load(fromByteOffset: $0, as: UInt8.self) }
                        macs[name] = bytes.map { String(format: "%02X", $0) }.joined(separator: ":")
                    }
                }
            }
            ptr = ifa.ifa_next
        }

        let candidates = [routeIf].compactMap { $0 } + v4.keys.sorted().filter { $0.hasPrefix("en") }
        guard let iface = candidates.first(where: { v4[$0] != nil && !$0.hasPrefix("utun") }) ?? candidates.first(where: { v4[$0] != nil }),
              let addr = v4[iface] else { return nil }

        let prefix = IPv4.prefixLength(addr.mask)
        var cidr = "\(IPv4.toString(addr.ip & addr.mask))/\(prefix)"
        var note: String?
        if prefix < 22 {
            cidr = "\(IPv4.toString(addr.ip & 0xFFFF_FF00))/24"
            note = "Großes Netz (/\(prefix)) – es wird nur das eigene /24 gescannt. Eigenes Ziel unten eintragen."
        }
        if let c = customCIDR?.trimmingCharacters(in: .whitespaces), !c.isEmpty {
            if IPv4.hosts(cidr: c) != nil { cidr = c; note = nil } else { note = "Ungültiges Ziel „\(c)“ (erlaubt: /16 bis /32, max. 4096 Hosts)." }
        }

        let dnsOut = Shell.run("/usr/sbin/scutil", ["--dns"])
        var dns: [String] = []
        for m in dnsOut.allMatches(#"nameserver\[\d+\]\s*:\s*([\d.]+)"#) where !dns.contains(m[1]) { dns.append(m[1]) }

        var ssid: String?
        let summary = Shell.run("/usr/sbin/ipconfig", ["getsummary", iface])
        if let s = summary.firstMatch(#"(?m)^\s+SSID\s*:\s*(.+)$"#)?[1], !s.contains("redacted") { ssid = s.trimmingCharacters(in: .whitespaces) }

        return NetworkInfo(
            interface: iface,
            ip: IPv4.toString(addr.ip),
            netmask: IPv4.toString(addr.mask),
            prefix: prefix,
            mac: macs[iface],
            gateway: gateway,
            dns: dns,
            ssid: ssid,
            cidr: cidr,
            hosts: IPv4.hosts(cidr: cidr) ?? [],
            note: note
        )
    }
}

// MARK: - Hersteller-Datenbank

final class VendorDB {
    static let shared = VendorDB()
    private var table: [String: String] = [:]

    private init() {
        guard let url = Bundle.main.url(forResource: "oui", withExtension: "txt") ?? Self.devURL(),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        for line in text.split(separator: "\n") {
            guard let tab = line.firstIndex(of: "\t") else { continue }
            table[String(line[..<tab])] = String(line[line.index(after: tab)...])
        }
    }

    private static func devURL() -> URL? {
        // Beim Start per `swift run` liegt die Datei im Projektordner.
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/oui.txt")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    var count: Int { table.count }

    func lookup(_ mac: String) -> String? {
        let hex = mac.replacingOccurrences(of: ":", with: "").uppercased()
        for n in [9, 7, 6] where hex.count >= n {
            if let v = table[String(hex.prefix(n))] { return v }
        }
        return nil
    }

    /// Lokal verwaltete (meist zufällige/private) MAC-Adresse?
    static func isRandomized(_ mac: String) -> Bool {
        guard let first = UInt8(mac.prefix(2), radix: 16) else { return false }
        return first & 0x02 != 0
    }
}
