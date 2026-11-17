import Foundation
import Darwin

enum BonjourTypes {
    /// Bekannte Diensttypen. Müssen auch in Info.plist (NSBonjourServices) stehen.
    static let known: [String: String] = [
        "_airplay._tcp.": "AirPlay",
        "_raop._tcp.": "AirPlay-Audio",
        "_companion-link._tcp.": "Apple Companion",
        "_device-info._tcp.": "Geräteinfo",
        "_homekit._tcp.": "HomeKit",
        "_hap._tcp.": "HomeKit-Zubehör",
        "_hap._udp.": "HomeKit (Thread)",
        "_sleep-proxy._udp.": "Bonjour Sleep Proxy",
        "_apple-mobdev2._tcp.": "Apple Mobilgerät",
        "_remotepairing._tcp.": "Apple Remote Pairing",
        "_touch-able._tcp.": "Apple Remote",
        "_appletv-v2._tcp.": "Apple TV",
        "_mediaremotetv._tcp.": "Apple TV Remote",
        "_airport._tcp.": "AirPort",
        "_afpovertcp._tcp.": "AFP-Freigabe",
        "_smb._tcp.": "SMB-Freigabe",
        "_adisk._tcp.": "Time Machine",
        "_nfs._tcp.": "NFS",
        "_ssh._tcp.": "SSH",
        "_sftp-ssh._tcp.": "SFTP",
        "_rfb._tcp.": "Bildschirmfreigabe (VNC)",
        "_workstation._tcp.": "Workstation",
        "_http._tcp.": "Webserver",
        "_https._tcp.": "Webserver (TLS)",
        "_ipp._tcp.": "Drucker (IPP)",
        "_ipps._tcp.": "Drucker (IPPS)",
        "_printer._tcp.": "Drucker (LPD)",
        "_pdl-datastream._tcp.": "Drucker (RAW)",
        "_scanner._tcp.": "Scanner",
        "_uscan._tcp.": "Scanner (eSCL)",
        "_googlecast._tcp.": "Google Cast",
        "_spotify-connect._tcp.": "Spotify Connect",
        "_sonos._tcp.": "Sonos",
        "_amzn-wplay._tcp.": "Amazon Fire TV",
        "_androidtvremote2._tcp.": "Android TV",
        "_nvstream._tcp.": "NVIDIA GameStream",
        "_hue._tcp.": "Philips Hue",
        "_home-assistant._tcp.": "Home Assistant",
        "_esphomelib._tcp.": "ESPHome",
        "_matter._tcp.": "Matter",
        "_matterc._udp.": "Matter (Inbetriebnahme)",
        "_meshcop._udp.": "Thread Border Router",
        "_trel._udp.": "Thread",
        "_mqtt._tcp.": "MQTT",
        "_daap._tcp.": "iTunes-Mediathek",
        "_dacp._tcp.": "iTunes Remote",
        "_plexmediasvr._tcp.": "Plex",
        "_teamviewer._tcp.": "TeamViewer",
        "_rdp._tcp.": "Remotedesktop",
        "_elg._tcp.": "Elgato",
        "_philipstv_rpc._tcp.": "Philips TV",
        "_viziocast._tcp.": "Vizio Cast",
        "_xbox._tcp.": "Xbox",
        "_ewelink._tcp.": "eWeLink",
        "_miio._udp.": "Xiaomi",
        "_shelly._tcp.": "Shelly",
    ]

    static func label(for type: String) -> String {
        let t = type.hasSuffix(".") ? type : type + "."
        return known[t] ?? type.replacingOccurrences(of: "._tcp.", with: "").replacingOccurrences(of: "._udp.", with: "").replacingOccurrences(of: "_", with: "")
    }
}

/// Durchsucht das lokale Netz per Bonjour/mDNS und löst jeden Dienst auf (IP, Port, TXT-Daten).
final class BonjourScanner: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    struct Found { let ip: String; let service: BonjourService }

    private var browsers: [String: NetServiceBrowser] = [:]
    private var pending: [NetService] = []
    private var results: [Found] = []
    private var meta: NetServiceBrowser?

    @MainActor
    func browse(duration: Double) async -> [Found] {
        results = []
        let m = NetServiceBrowser()
        m.delegate = self
        m.searchForServices(ofType: "_services._dns-sd._udp.", inDomain: "local.")
        meta = m
        for t in BonjourTypes.known.keys { startBrowser(t) }
        try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
        stop()
        return results
    }

    @MainActor
    func stop() {
        meta?.stop(); meta = nil
        browsers.values.forEach { $0.stop() }
        browsers = [:]
        pending.forEach { $0.stop() }
        pending = []
    }

    private func startBrowser(_ type: String) {
        guard browsers[type] == nil else { return }
        let b = NetServiceBrowser()
        b.delegate = self
        b.searchForServices(ofType: type, inDomain: "local.")
        browsers[type] = b
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        if browser === meta {
            // Bei der Meta-Abfrage ist der "Name" der Diensttyp, z. B. "_airplay" + "_tcp.local."
            let proto = service.type.components(separatedBy: ".").first ?? "_tcp"
            startBrowser("\(service.name).\(proto).")
            return
        }
        service.delegate = self
        pending.append(service)
        service.resolve(withTimeout: 5)
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        var txt: [String: String] = [:]
        if let data = sender.txtRecordData() {
            for (k, v) in NetService.dictionary(fromTXTRecord: data) {
                let s = String(decoding: v, as: UTF8.self).printableCleaned
                txt[k] = s
            }
        }
        var ips: [String] = []
        for addr in sender.addresses ?? [] {
            addr.withUnsafeBytes { raw in
                guard raw.count >= MemoryLayout<sockaddr_in>.size else { return }
                let sa = raw.loadUnaligned(as: sockaddr.self)
                if sa.sa_family == UInt8(AF_INET) {
                    let sin = raw.loadUnaligned(as: sockaddr_in.self)
                    ips.append(IPv4.string(sin.sin_addr))
                }
            }
        }
        let svc = BonjourService(name: sender.name, type: sender.type, port: sender.port, hostName: sender.hostName, txt: txt)
        for ip in Set(ips) where !results.contains(where: { $0.ip == ip && $0.service.id == svc.id }) {
            results.append(Found(ip: ip, service: svc))
        }
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {}
}
