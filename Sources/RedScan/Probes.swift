import Foundation
import Darwin

// MARK: - Ping

struct PingResult { let ttl: Int; let time: Double }

enum Ping {
    static func ping(_ ip: String, timeoutMs: Int = 900) -> PingResult? {
        let out = Shell.run("/sbin/ping", ["-n", "-c", "1", "-W", "\(timeoutMs)", "-t", "2", ip])
        guard let m = out.firstMatch(#"ttl=(\d+) time=([\d.]+)"#) else { return nil }
        return PingResult(ttl: Int(m[1]) ?? 0, time: Double(m[2]) ?? 0)
    }
}

// MARK: - ARP

enum ARP {
    struct Entry { let ip: String; let mac: String; let iface: String }

    static func table() -> [Entry] {
        let out = Shell.run("/usr/sbin/arp", ["-an"])
        return out.allMatches(#"\(([\d.]+)\) at ([0-9a-fA-F:]+) on (\w+)"#).compactMap { m in
            let mac = normalizeMAC(m[2])
            guard mac != "FF:FF:FF:FF:FF:FF", !mac.hasPrefix("01:00:5E") else { return nil }
            return Entry(ip: m[1], mac: mac, iface: m[3])
        }
    }
}

// MARK: - Ports

enum Ports {
    static let names: [Int: String] = [
        20: "FTP-Daten", 21: "FTP", 22: "SSH", 23: "Telnet", 25: "SMTP", 53: "DNS", 80: "HTTP", 81: "HTTP-Alt",
        88: "Kerberos", 110: "POP3", 111: "RPC", 135: "MS-RPC", 139: "NetBIOS-Session", 143: "IMAP", 389: "LDAP",
        443: "HTTPS", 445: "SMB (Dateifreigabe)", 465: "SMTPS", 515: "LPD (Drucker)", 548: "AFP (Apple-Freigabe)",
        554: "RTSP (Kamera/Stream)", 587: "SMTP-Submission", 631: "IPP (Drucker)", 853: "DNS-over-TLS", 993: "IMAPS",
        995: "POP3S", 1080: "SOCKS-Proxy", 1400: "Sonos", 1433: "MS-SQL", 1521: "Oracle DB", 1723: "PPTP-VPN",
        1883: "MQTT (IoT)", 2049: "NFS", 2375: "Docker-API", 3000: "Web-App", 3306: "MySQL", 3389: "RDP (Remotedesktop)",
        3689: "DAAP (iTunes)", 4070: "Spotify Connect", 5000: "UPnP / Web", 5001: "Synology DSM", 5060: "SIP (VoIP)",
        5222: "XMPP", 5357: "WSD (Windows)", 5432: "PostgreSQL", 5555: "ADB (Android Debug)", 5900: "VNC",
        6379: "Redis", 6443: "Kubernetes", 6668: "Tuya (Smart Home)", 7000: "AirPlay", 7100: "AirPlay-Screen",
        8000: "HTTP-Alt", 8008: "Chromecast", 8009: "Chromecast", 8060: "Roku", 8080: "HTTP-Proxy", 8081: "HTTP-Alt",
        8123: "Home Assistant", 8291: "MikroTik Winbox", 8443: "HTTPS-Alt", 8888: "HTTP-Alt", 9000: "Web-Admin",
        9090: "Web-Admin", 9100: "JetDirect (Drucker)", 9200: "Elasticsearch", 10000: "Webmin", 32400: "Plex",
        49000: "FRITZ!Box TR-064", 49152: "UPnP", 62078: "iPhone/iPad-Sync",
    ]

    static var common: [Int] { names.keys.sorted() }
    static var deep: [Int] { Array(Set(Array(1...1024) + common + [1900, 2000, 2869, 3001, 4000, 4443, 5353, 7443, 8001, 8002, 8082, 8088, 8090, 8181, 8200, 8880, 9001, 9443, 10001, 37777, 50000])).sorted() }

    static let httpPorts: Set<Int> = [80, 81, 3000, 5000, 8000, 8008, 8080, 8081, 8088, 8090, 8123, 8181, 8880, 8888, 9000, 9090, 10000, 32400, 49000]
    static let httpsPorts: Set<Int> = [443, 5001, 4443, 7443, 8443, 9443]
    static let bannerPorts: Set<Int> = [21, 22, 23, 25, 110, 143, 587, 3306, 5900, 6379]

    static func label(_ p: Int) -> String { names[p] ?? "Unbekannt" }

    /// Paralleler TCP-Connect-Scan: alle Sockets eines Blocks gleichzeitig, ein gemeinsames poll().
    static func scan(ip: String, ports: [Int], timeoutMs: Int = 800) -> [Int] {
        var open: [Int] = []
        for chunk in ports.chunked(200) {
            var pending: [(fd: Int32, port: Int)] = []
            for p in chunk {
                let fd = socket(AF_INET, SOCK_STREAM, 0)
                guard fd >= 0 else { continue }
                _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) | O_NONBLOCK)
                var one: Int32 = 1
                setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
                var addr = sockaddr_in.make(ip, UInt16(p))
                let r = withUnsafePointer(to: &addr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
                }
                if r == 0 { open.append(p); close(fd) }
                else if errno == EINPROGRESS { pending.append((fd, p)) }
                else { close(fd) }
            }
            let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000)
            while !pending.isEmpty {
                let remaining = Int32(deadline.timeIntervalSinceNow * 1000)
                if remaining <= 0 { break }
                var pfds = pending.map { pollfd(fd: $0.fd, events: Int16(POLLOUT), revents: 0) }
                let r = poll(&pfds, nfds_t(pfds.count), remaining)
                if r < 0 && errno == EINTR { continue }
                if r <= 0 { break }
                var still: [(fd: Int32, port: Int)] = []
                for (i, pfd) in pfds.enumerated() {
                    if pfd.revents != 0 {
                        var err: Int32 = 0
                        var len = socklen_t(MemoryLayout<Int32>.size)
                        getsockopt(pfd.fd, SOL_SOCKET, SO_ERROR, &err, &len)
                        if err == 0 && pfd.revents & Int16(POLLOUT) != 0 { open.append(pending[i].port) }
                        close(pfd.fd)
                    } else {
                        still.append(pending[i])
                    }
                }
                pending = still
            }
            pending.forEach { close($0.fd) }
        }
        return open.sorted()
    }

    /// Verbindet sich und liest die Begrüßung des Dienstes (z. B. "SSH-2.0-OpenSSH_9.6").
    static func banner(ip: String, port: Int, timeoutMs: Int = 1200) -> String? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) | O_NONBLOCK)
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in.make(ip, UInt16(port))
        let r = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        if r != 0 {
            guard errno == EINPROGRESS else { return nil }
            var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
            guard poll(&pfd, 1, Int32(timeoutMs)) > 0 else { return nil }
        }
        var data = [UInt8]()
        var buf = [UInt8](repeating: 0, count: 2048)
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000)
        while data.count < 2048 {
            let remaining = Int32(deadline.timeIntervalSinceNow * 1000)
            if remaining <= 0 { break }
            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            guard poll(&pfd, 1, remaining) > 0 else { break }
            let n = read(fd, &buf, buf.count)
            if n <= 0 { break }
            data += buf[0..<n]
            if data.contains(0x0A) { break }
        }
        guard !data.isEmpty else { return nil }
        let text = String(decoding: data, as: UTF8.self).printableCleaned
        return text.isEmpty ? nil : String(text.prefix(200))
    }
}

// MARK: - NetBIOS (Windows-/Samba-Namen)

enum NetBIOS {
    struct Result { var name: String?; var group: String?; var mac: String? }

    static func query(_ ips: [String], timeout: Double = 2.0) -> [String: Result] {
        guard let sock = UDPSocket() else { return [:] }
        var q: [UInt8] = [0x13, 0x37, 0x00, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0, 0x20]
        var name = [UInt8](repeating: 0, count: 16)
        name[0] = 0x2A // "*"
        for b in name { q.append(0x41 + (b >> 4)); q.append(0x41 + (b & 0x0F)) }
        q += [0x00, 0x00, 0x21, 0x00, 0x01]
        for ip in ips { sock.send(Data(q), to: ip, port: 137) }

        var results: [String: Result] = [:]
        sock.receive(for: timeout) { ip, b in
            guard b.count > 57 else { return }
            let num = Int(b[56])
            guard b.count >= 57 + num * 18 else { return }
            var r = Result()
            for i in 0..<num {
                let off = 57 + i * 18
                let n = String(decoding: b[off..<off + 15], as: UTF8.self).trimmingCharacters(in: .whitespaces.union(.controlCharacters))
                let suffix = b[off + 15]
                let isGroup = b[off + 16] & 0x80 != 0
                if suffix == 0x00 && !isGroup && r.name == nil { r.name = n }
                if suffix == 0x00 && isGroup && r.group == nil { r.group = n }
            }
            let macOff = 57 + num * 18
            if b.count >= macOff + 6 {
                let mac = b[macOff..<macOff + 6].map { String(format: "%02X", $0) }.joined(separator: ":")
                if mac != "00:00:00:00:00:00" { r.mac = mac }
            }
            results[ip] = r
        }
        return results
    }
}

// MARK: - DNS-Hilfen (für mDNS)

enum DNSWire {
    static func encodeName(_ name: String) -> [UInt8] {
        var out: [UInt8] = []
        for label in name.split(separator: ".") {
            let bytes = Array(label.utf8)
            out.append(UInt8(bytes.count)); out += bytes
        }
        out.append(0)
        return out
    }

    /// Liest einen (ggf. komprimierten) DNS-Namen ab `offset`.
    static func readName(_ b: [UInt8], _ offset: inout Int) -> String? {
        var labels: [String] = []
        var pos = offset
        var jumped = false
        var hops = 0
        while pos < b.count {
            let len = Int(b[pos])
            if len == 0 { pos += 1; break }
            if len & 0xC0 == 0xC0 {
                guard pos + 1 < b.count, hops < 20 else { return nil }
                let ptr = (len & 0x3F) << 8 | Int(b[pos + 1])
                if !jumped { offset = pos + 2 }
                jumped = true; hops += 1
                pos = ptr
                continue
            }
            guard pos + 1 + len <= b.count else { return nil }
            labels.append(String(decoding: b[(pos + 1)..<(pos + 1 + len)], as: UTF8.self))
            pos += 1 + len
        }
        if !jumped { offset = pos }
        return labels.joined(separator: ".")
    }
}

enum MDNS {
    /// Fragt jedes Gerät direkt per mDNS nach seinem Namen (PTR auf x.x.x.x.in-addr.arpa).
    static func reverse(_ ips: [String], timeout: Double = 2.5) -> [String: String] {
        guard let sock = UDPSocket() else { return [:] }
        for ip in ips {
            let rev = ip.split(separator: ".").reversed().joined(separator: ".") + ".in-addr.arpa"
            var q: [UInt8] = [0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0]
            q += DNSWire.encodeName(rev)
            q += [0x00, 0x0C, 0x00, 0x01]
            sock.send(Data(q), to: ip, port: 5353)
        }
        var out: [String: String] = [:]
        sock.receive(for: timeout) { ip, b in
            if let name = firstPTR(b) { out[ip] = name }
        }
        return out
    }

    static func firstPTR(_ b: [UInt8]) -> String? {
        guard b.count > 12 else { return nil }
        let qd = Int(b[4]) << 8 | Int(b[5])
        let an = Int(b[6]) << 8 | Int(b[7])
        var off = 12
        for _ in 0..<qd {
            guard DNSWire.readName(b, &off) != nil else { return nil }
            off += 4
        }
        for _ in 0..<an {
            guard DNSWire.readName(b, &off) != nil, off + 10 <= b.count else { return nil }
            let type = Int(b[off]) << 8 | Int(b[off + 1])
            let rdlen = Int(b[off + 8]) << 8 | Int(b[off + 9])
            off += 10
            if type == 12 {
                var o = off
                if let n = DNSWire.readName(b, &o), !n.isEmpty { return n }
            }
            off += rdlen
        }
        return nil
    }
}

// MARK: - Reverse DNS

enum ReverseDNS {
    static func lookup(_ ips: [String], timeout: Double = 4) -> [String: String] {
        let lock = NSLock()
        var out: [String: String] = [:]
        let group = DispatchGroup()
        for ip in ips {
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                defer { group.leave() }
                var addr = sockaddr_in.make(ip, 0)
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let r = withUnsafePointer(to: &addr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        getnameinfo($0, socklen_t(MemoryLayout<sockaddr_in>.size), &host, socklen_t(host.count), nil, 0, NI_NAMEREQD)
                    }
                }
                if r == 0 {
                    let name = String(cString: host)
                    if name != ip { lock.lock(); out[ip] = name; lock.unlock() }
                }
            }
        }
        _ = group.wait(timeout: .now() + timeout)
        lock.lock(); defer { lock.unlock() }
        return out
    }
}

// MARK: - SSDP / UPnP

enum SSDP {
    struct Response { let ip: String; let headers: [String: String] }

    static func discover(timeout: Double = 3.5) -> [Response] {
        guard let sock = UDPSocket() else { return [] }
        for st in ["ssdp:all", "upnp:rootdevice"] {
            let msg = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 2\r\nST: \(st)\r\n\r\n"
            for _ in 0..<2 { sock.send(Data(msg.utf8), to: "239.255.255.250", port: 1900) }
        }
        var out: [Response] = []
        sock.receive(for: timeout) { ip, b in
            var headers: [String: String] = [:]
            for line in String(decoding: b, as: UTF8.self).components(separatedBy: "\r\n") {
                guard let c = line.firstIndex(of: ":") else { continue }
                headers[line[..<c].trimmingCharacters(in: .whitespaces).uppercased()] = line[line.index(after: c)...].trimmingCharacters(in: .whitespaces)
            }
            out.append(Response(ip: ip, headers: headers))
        }
        return out
    }

    final class DescriptionParser: NSObject, XMLParserDelegate {
        static let wanted: Set<String> = ["friendlyName", "manufacturer", "modelName", "modelNumber", "modelDescription", "serialNumber", "deviceType", "presentationURL"]
        var fields: [String: String] = [:]
        private var text = ""
        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) { text = "" }
        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            let key = elementName.components(separatedBy: ":").last ?? elementName
            let v = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if Self.wanted.contains(key), fields[key] == nil, !v.isEmpty { fields[key] = v }
            text = ""
        }
    }

    static func describe(location: String, server: String?) async -> UPnPInfo {
        var info = UPnPInfo(location: location, server: server)
        guard let url = URL(string: location) else { return info }
        var req = URLRequest(url: url, timeoutInterval: 4)
        req.setValue("RedScan/1.0 UPnP/1.1", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await Web.session.data(for: req) else { return info }
        let parser = XMLParser(data: data)
        let d = DescriptionParser()
        parser.delegate = d
        parser.parse()
        let f = d.fields
        info.friendlyName = f["friendlyName"]; info.manufacturer = f["manufacturer"]; info.modelName = f["modelName"]
        info.modelNumber = f["modelNumber"]; info.modelDescription = f["modelDescription"]; info.serialNumber = f["serialNumber"]
        info.deviceType = f["deviceType"]; info.presentationURL = f["presentationURL"]
        return info
    }
}

// MARK: - Web / TLS

enum Web {
    final class TrustAllDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
        private let lock = NSLock()
        private var certs: [String: String] = [:]

        func certificate(for host: String) -> String? { lock.lock(); defer { lock.unlock() }; return certs[host] }

        func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            guard let trust = challenge.protectionSpace.serverTrust else { completionHandler(.performDefaultHandling, nil); return }
            if let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let leaf = chain.first,
               let summary = SecCertificateCopySubjectSummary(leaf) as String? {
                let key = "\(challenge.protectionSpace.host):\(challenge.protectionSpace.port)"
                lock.lock(); certs[key] = summary; lock.unlock()
            }
            completionHandler(.useCredential, URLCredential(trust: trust))
        }
    }

    static let delegate = TrustAllDelegate()
    static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 4
        cfg.timeoutIntervalForResource = 7
        cfg.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: cfg, delegate: delegate, delegateQueue: nil)
    }()

    static func fetch(ip: String, port: Int, tls: Bool) async -> HTTPInfo? {
        guard let url = URL(string: "\(tls ? "https" : "http")://\(ip):\(port)/") else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 4)
        req.setValue("Mozilla/5.0 (Macintosh) RedScan/1.0", forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await session.data(for: req), let h = resp as? HTTPURLResponse else {
            if tls, let cert = delegate.certificate(for: "\(ip):\(port)") {
                return HTTPInfo(port: port, tls: tls, certificate: cert)
            }
            return nil
        }
        let body = String(decoding: data.prefix(300_000), as: UTF8.self)
        var title = body.firstMatch(#"<title[^>]*>(.*?)</title>"#, options: [.caseInsensitive, .dotMatchesLineSeparators])?[1]
        title = title.map(decodeEntities)?.printableCleaned
        if title?.isEmpty == true { title = nil }
        return HTTPInfo(
            port: port, tls: tls, status: h.statusCode,
            server: h.value(forHTTPHeaderField: "Server"),
            poweredBy: h.value(forHTTPHeaderField: "X-Powered-By"),
            title: title.map { String($0.prefix(120)) },
            certificate: tls ? delegate.certificate(for: "\(ip):\(port)") : nil,
            finalURL: h.url?.absoluteString != url.absoluteString ? h.url?.absoluteString : nil
        )
    }

    static func decodeEntities(_ s: String) -> String {
        var r = s
        for (k, v) in ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&nbsp;": " ", "&auml;": "ä", "&ouml;": "ö", "&uuml;": "ü", "&szlig;": "ß"] {
            r = r.replacingOccurrences(of: k, with: v)
        }
        return r
    }

    static func publicIP() async -> String? {
        guard let (data, _) = try? await URLSession.shared.data(from: URL(string: "https://api.ipify.org")!) else { return nil }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
