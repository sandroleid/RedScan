import Foundation

/// Heuristik: Aus Hersteller, Namen, Diensten und Ports den Gerätetyp ableiten.
enum Classifier {
    static func classify(_ d: Device) -> DeviceKind {
        if d.isSelf { return .thisMac }
        if d.isGateway { return .router }

        let v = (d.vendor ?? "").lowercased()
        let model = (d.model ?? "").lowercased()
        let names = ([d.mdnsName, d.hostname, d.netbiosName] + d.services.map { $0.name } + d.upnp.flatMap { [$0.friendlyName, $0.modelName, $0.modelDescription] })
            .compactMap { $0 }.joined(separator: " ").lowercased()
        let types = Set(d.services.map { $0.type.lowercased() })
        let ports = Set(d.openPorts.map(\.port))
        let upnp = d.upnp.compactMap(\.deviceType).joined(separator: " ").lowercased()
        func has(_ t: String) -> Bool { types.contains { $0.hasPrefix(t) } }
        func vendorIs(_ list: [String]) -> Bool { list.contains { v.contains($0) } }
        func nameHas(_ list: [String]) -> Bool { list.contains { names.contains($0) } }

        // 1. Apple-Modellkennung aus Bonjour (_device-info / AirPlay)
        if !model.isEmpty {
            if model.hasPrefix("iphone") { return .phone }
            if model.hasPrefix("ipad") { return .tablet }
            if model.hasPrefix("watch") { return .watch }
            if model.hasPrefix("appletv") { return .tv }
            if model.hasPrefix("audioaccessory") { return .speaker }
            if model.contains("macbook") { return .laptop }
            if model.hasPrefix("imac") || model.hasPrefix("macmini") || model.hasPrefix("macpro") || model.hasPrefix("mac") { return .computer }
        }

        // 2. Eindeutige Namen
        if nameHas(["iphone", "galaxy-s", "pixel", "android", "redmi", "oneplus", "huawei-p", "smartphone"]) { return .phone }
        if nameHas(["ipad", "galaxy-tab", "tablet"]) { return .tablet }
        if nameHas(["macbook", "laptop-", "thinkpad", "notebook"]) { return .laptop }
        if nameHas(["playstation", "ps4", "ps5", "xbox", "nintendo", "switch"]) { return .console }
        if nameHas(["fritz!box", "fritzbox", "speedport", "router", "repeater", "access point", "unifi"]) { return .router }
        if nameHas(["imac", "mac-mini", "macmini", "desktop-", "-pc"]) { return .computer }

        // 3. Dienste & Ports
        if has("_ipp") || has("_printer") || has("_pdl-datastream") || has("_uscan") || ports.contains(9100) || ports.contains(631) || ports.contains(515)
            || vendorIs(["hewlett", "hp inc", "brother", "canon", "seiko epson", "epson", "xerox", "kyocera", "lexmark", "ricoh"]) { return .printer }
        if vendorIs(["sonos"]) || has("_sonos") || ports.contains(1400) { return .speaker }
        if has("_googlecast") || has("_amzn-wplay") || has("_androidtvremote") || has("_appletv") || has("_mediaremotetv") || ports.contains(8008) || ports.contains(8060)
            || upnp.contains("mediarenderer") && vendorIs(["samsung", "lg ", "sony", "philips", "tcl", "hisense", "panasonic", "vizio"])
            || vendorIs(["roku"]) { return .tv }
        if vendorIs(["synology", "qnap", "western digital", "buffalo", "asustor"]) || (ports.contains(5000) && ports.contains(5001)) || has("_adisk") { return .nas }
        if vendorIs(["hikvision", "dahua", "axis comm", "reolink", "arlo", "wyze", "ezviz", "foscam", "amcrest"]) || (ports.contains(554) && !ports.contains(7000)) { return .camera }
        if vendorIs(["nintendo", "sony interactive"]) { return .console }
        if has("_hap") || has("_homekit") || has("_hue") || has("_esphomelib") || has("_matter") || has("_shelly") || has("_miio") || has("_ewelink") || ports.contains(1883) || ports.contains(6668) || ports.contains(8123)
            || vendorIs(["espressif", "tuya", "shelly", "signify", "philips lighting", "xiaomi", "lumi", "tasmota", "ring ", "nest", "ecobee", "tado", "bosch", "eq-3", "ikea", "lifx", "meross", "sonoff"]) { return .iot }
        if vendorIs(["amazon"]) { return .speaker }
        if ports.contains(62078) || has("_apple-mobdev") || has("_remotepairing") { return .phone }
        if vendorIs(["avm", "tp-link", "netgear", "ubiquiti", "cisco", "linksys", "zyxel", "mikrotik", "juniper", "aruba", "d-link", "draytek", "lancom", "sagemcom", "arcadyan", "technicolor"])
            || ports.contains(8291) || ports.contains(49000) { return .router }
        if vendorIs(["raspberry"]) { return .server }
        if ports.contains(3389) || ports.contains(135) || ports.contains(5357) || d.netbiosName != nil { return .computer }
        if has("_afpovertcp") || has("_rfb") || ports.contains(548) || ports.contains(5900) { return .computer }
        if ports.contains(22) && (ports.contains(80) || ports.contains(443) || ports.contains(3306) || ports.contains(5432)) { return .server }
        if vendorIs(["samsung", "lg electronics", "oppo", "vivo", "huawei", "honor", "motorola", "oneplus", "realme", "google"]) && ports.isEmpty { return .phone }
        if vendorIs(["intel", "dell", "lenovo", "asustek", "micro-star", "gigabyte", "liteon", "azurewave", "realtek"]) { return .computer }
        if has("_companion-link") { return .computer }
        if d.randomizedMAC && ports.isEmpty { return .phone }
        return .unknown
    }

    static func appleModel(from services: [BonjourService]) -> String? {
        for s in services {
            for key in ["model", "am", "md"] {
                if let m = s.txt[key], !m.isEmpty, m.count < 60 { return m }
            }
        }
        return nil
    }

    /// Übersetzt Apple-Modellkennungen in Klartext (Auswahl).
    static func prettyModel(_ m: String) -> String {
        let l = m.lowercased()
        let map: [(String, String)] = [
            ("macbookpro", "MacBook Pro"), ("macbookair", "MacBook Air"), ("macbook", "MacBook"), ("imac", "iMac"),
            ("macmini", "Mac mini"), ("macpro", "Mac Pro"), ("mac1", "Mac (Apple Silicon)"), ("mac", "Mac"), ("iphone", "iPhone"), ("ipad", "iPad"),
            ("appletv", "Apple TV"), ("audioaccessory1", "HomePod"), ("audioaccessory5", "HomePod mini"), ("audioaccessory6", "HomePod (2. Gen.)"),
            ("audioaccessory", "HomePod"), ("watch", "Apple Watch"),
        ]
        for (k, v) in map where l.hasPrefix(k) { return "\(v) (\(m))" }
        return m
    }
}
