import Foundation
import SystemConfiguration

enum DeviceKind: String, Codable, CaseIterable {
    case thisMac, router, computer, laptop, phone, tablet, tv, speaker, printer, nas, camera, iot, console, server, watch, unknown

    var label: String {
        switch self {
        case .thisMac: return "Dieser Mac"
        case .router: return "Router / AP"
        case .computer: return "Computer"
        case .laptop: return "Laptop"
        case .phone: return "Smartphone"
        case .tablet: return "Tablet"
        case .tv: return "TV / Streaming"
        case .speaker: return "Lautsprecher"
        case .printer: return "Drucker"
        case .nas: return "NAS / Speicher"
        case .camera: return "Kamera"
        case .iot: return "Smart Home / IoT"
        case .console: return "Spielkonsole"
        case .server: return "Server"
        case .watch: return "Watch"
        case .unknown: return "Unbekannt"
        }
    }

    var symbol: String {
        switch self {
        case .thisMac: return "laptopcomputer.and.arrow.down"
        case .router: return "wifi.router"
        case .computer: return "desktopcomputer"
        case .laptop: return "laptopcomputer"
        case .phone: return "iphone"
        case .tablet: return "ipad.landscape"
        case .tv: return "tv"
        case .speaker: return "hifispeaker"
        case .printer: return "printer"
        case .nas: return "externaldrive.connected.to.line.below"
        case .camera: return "web.camera"
        case .iot: return "lightbulb"
        case .console: return "gamecontroller"
        case .server: return "server.rack"
        case .watch: return "applewatch"
        case .unknown: return "questionmark.circle"
        }
    }
}

struct OpenPort: Codable, Hashable, Identifiable {
    var id: Int { port }
    let port: Int
    var service: String
    var banner: String?
}

struct BonjourService: Codable, Hashable, Identifiable {
    var id: String { type + "|" + name }
    let name: String
    let type: String
    let port: Int
    let hostName: String?
    var txt: [String: String]

    var typeLabel: String { BonjourTypes.label(for: type) }
}

struct UPnPInfo: Codable, Hashable {
    var location: String
    var server: String?
    var friendlyName: String?
    var manufacturer: String?
    var modelName: String?
    var modelNumber: String?
    var modelDescription: String?
    var serialNumber: String?
    var deviceType: String?
    var presentationURL: String?
}

struct HTTPInfo: Codable, Hashable, Identifiable {
    var id: Int { port }
    let port: Int
    let tls: Bool
    var status: Int?
    var server: String?
    var poweredBy: String?
    var title: String?
    var certificate: String?
    var finalURL: String?
}

struct Device: Identifiable, Codable, Hashable {
    var id: String { ip }
    let ip: String
    var mac: String?
    var vendor: String?
    var randomizedMAC = false
    var hostname: String?
    var mdnsName: String?
    var netbiosName: String?
    var netbiosGroup: String?
    var latencyMs: Double?
    var ttl: Int?
    var openPorts: [OpenPort] = []
    var services: [BonjourService] = []
    var upnp: [UPnPInfo] = []
    var http: [HTTPInfo] = []
    var model: String?
    var kind: DeviceKind = .unknown
    var isGateway = false
    var isSelf = false
    var portsScanned = false
    var deepScanned = false
    var discoveredBy: Set<String> = []
    var firstSeen = Date()

    init(ip: String) { self.ip = ip }

    var ipSortKey: UInt32 { IPv4.toUInt32(ip) ?? 0 }

    /// Gerätename des Macs (schnell, ohne DNS-Abfragen wie Host.current()).
    static let computerName: String? = SCDynamicStoreCopyComputerName(nil, nil) as String?

    var displayName: String {
        if isSelf, let h = Self.computerName { return h }
        if let f = upnp.compactMap(\.friendlyName).first, !f.isEmpty { return f }
        if let s = services.first(where: { $0.type.hasPrefix("_device-info") || $0.type.hasPrefix("_companion-link") || $0.type.hasPrefix("_airplay") || $0.type.hasPrefix("_googlecast") }) {
            if let fn = s.txt["fn"], !fn.isEmpty { return fn }
            return s.name
        }
        if let m = mdnsName { return m.replacingOccurrences(of: ".local", with: "").trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
        if let n = netbiosName { return n }
        if let s = services.first { return s.txt["fn"] ?? s.name }
        if let h = hostname { return h }
        if let v = vendor { return "\(v.components(separatedBy: CharacterSet(charactersIn: ",.")).first ?? v)-Gerät" }
        return ip
    }

    /// Alle Namen/Bezeichner in einem String – für Suche und Klassifizierung.
    var searchBlob: String {
        var parts: [String] = [ip, mac ?? "", vendor ?? "", hostname ?? "", mdnsName ?? "", netbiosName ?? "", netbiosGroup ?? "", model ?? "", kind.label]
        parts += services.map { "\($0.name) \($0.type) \($0.txt.values.joined(separator: " "))" }
        parts += upnp.map { [$0.friendlyName, $0.manufacturer, $0.modelName, $0.modelDescription, $0.deviceType, $0.server].compactMap { $0 }.joined(separator: " ") }
        parts += http.map { [$0.server, $0.title, $0.poweredBy].compactMap { $0 }.joined(separator: " ") }
        parts += openPorts.map { "\($0.port) \($0.service) \($0.banner ?? "")" }
        return parts.joined(separator: " ").lowercased()
    }

    var osGuess: String? {
        let blob = searchBlob
        if isSelf { return "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)" }
        if let m = model?.lowercased() {
            if m.hasPrefix("iphone") { return "iOS" }
            if m.hasPrefix("ipad") { return "iPadOS" }
            if m.hasPrefix("appletv") { return "tvOS" }
            if m.hasPrefix("audioaccessory") { return "HomePod-Software" }
            if m.contains("mac") || m.hasPrefix("imac") { return "macOS" }
            if m.hasPrefix("watch") { return "watchOS" }
        }
        if blob.contains("ubuntu") { return "Linux (Ubuntu)" }
        if blob.contains("debian") { return "Linux (Debian)" }
        if blob.contains("raspbian") || blob.contains("raspberry") { return "Linux (Raspberry Pi OS)" }
        if blob.contains("openwrt") { return "Linux (OpenWrt)" }
        if blob.contains("fritz") { return "FRITZ!OS" }
        if blob.contains("synology") || blob.contains("dsm") { return "Synology DSM" }
        if blob.contains("microsoft") || blob.contains("windows") || openPorts.contains(where: { [135, 3389].contains($0.port) }) { return "Windows" }
        if kind == .phone && (vendor?.lowercased().contains("apple") ?? false) { return "iOS" }
        if blob.contains("android") || openPorts.contains(where: { $0.port == 5555 }) { return "Android" }
        if openPorts.contains(where: { $0.port == 62078 }) { return "iOS / iPadOS" }
        if let ttl {
            if ttl > 128 { return "Netzwerk-OS (Router/Switch)" }
            if ttl > 64 { return "Windows (TTL \(ttl))" }
            if vendor?.lowercased().contains("apple") ?? false { return "Apple (iOS/macOS)" }
            return "Linux / Unix / Android (TTL \(ttl))"
        }
        return nil
    }
}

struct NetworkInfo: Hashable {
    var interface: String
    var ip: String
    var netmask: String
    var prefix: Int
    var mac: String?
    var gateway: String?
    var dns: [String]
    var ssid: String?
    var cidr: String
    var hosts: [String]
    var note: String?
}
