import SwiftUI
import AppKit

struct DetailView: View {
    @EnvironmentObject var scanner: NetScanner
    let device: Device
    let close: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                actions
                section("Identität", "person.text.rectangle") {
                    row("Name", device.displayName)
                    row("Typ", device.kind.label)
                    row("Modell", device.model.map(Classifier.prettyModel))
                    row("Betriebssystem", device.osGuess)
                    row("Hersteller", device.vendor)
                    row("UPnP-Hersteller", device.upnp.compactMap(\.manufacturer).first)
                    row("UPnP-Modell", device.upnp.compactMap { [$0.modelName, $0.modelNumber].compactMap { $0 }.joined(separator: " ").nilIfEmpty }.first)
                    row("Seriennummer", device.upnp.compactMap(\.serialNumber).first, mono: true)
                }
                section("Netzwerk", "network") {
                    row("IPv4", device.ip, mono: true)
                    row("MAC", device.mac, mono: true)
                    if device.randomizedMAC { row("MAC-Typ", "Privat / zufällig (lokal verwaltet)") }
                    row("Hostname (DNS)", device.hostname, mono: true)
                    row("mDNS-Name", device.mdnsName, mono: true)
                    row("NetBIOS-Name", device.netbiosName, mono: true)
                    row("Arbeitsgruppe", device.netbiosGroup, mono: true)
                    row("Latenz", device.latencyMs.map { String(format: "%.1f ms", $0) })
                    row("TTL", device.ttl.map(String.init))
                    row("Erkannt per", device.discoveredBy.sorted().joined(separator: ", "))
                    row("Zuerst gesehen", device.firstSeen.formatted(date: .omitted, time: .standard))
                }
                if let k = scanner.history.known(for: device) {
                    section("Verlauf", "clock.arrow.circlepath") {
                        row("Zuerst gesehen", k.firstSeen.formatted(date: .abbreviated, time: .shortened))
                        row("Zuletzt gesehen", k.lastSeen.formatted(date: .abbreviated, time: .shortened))
                        row("Gesehen", "\(k.seenCount)× bei Scans")
                        if k.ips.count > 1 { row("Frühere IPs", k.ips.filter { $0 != device.ip }.joined(separator: ", "), mono: true) }
                    }
                }
                portsSection
                if !device.http.isEmpty { webSection }
                if !device.services.isEmpty { servicesSection }
                if !device.upnp.isEmpty { upnpSection }
            }
            .padding(18)
        }
        .background(Theme.panel)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                KindIcon(kind: device.kind, size: 58)
                Spacer()
                Button(action: close) { Image(systemName: "xmark").font(.system(size: 12, weight: .bold)) }
                    .buttonStyle(.plain).foregroundStyle(Theme.dim).padding(6)
                    .background(Circle().fill(Theme.card))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(device.displayName).font(.system(size: 20, weight: .heavy, design: .rounded)).textSelection(.enabled)
                Text(device.ip).font(.system(size: 14, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.redBright).textSelection(.enabled)
                HStack(spacing: 5) {
                    Pill(text: device.kind.label, strong: true)
                    if device.isGateway { Pill(text: "Gateway") }
                    if device.isSelf { Pill(text: "Dieser Mac") }
                    if let os = device.osGuess { Pill(text: os) }
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [Theme.headerTint, Theme.card], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.red.opacity(0.3)))
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button {
                scanner.deepScan(device.ip)
            } label: {
                if scanner.busyDevices.contains(device.ip) {
                    HStack(spacing: 6) { ProgressView().controlSize(.small).tint(.white); Text("Scanne …") }
                } else {
                    Label(device.deepScanned ? "Erneut tief scannen" : "Tiefenscan", systemImage: "scope")
                }
            }
            .buttonStyle(RedButtonStyle())
            .disabled(scanner.busyDevices.contains(device.ip))
            .help("Scannt Ports 1–1024 plus bekannte Dienst-Ports")

            if let web = webURL {
                Button { NSWorkspace.shared.open(web) } label: { Image(systemName: "safari") }
                    .buttonStyle(RedButtonStyle(prominent: false)).help("Weboberfläche öffnen")
            }
            if let mac = device.mac, !device.isSelf {
                Button { scanner.wake(mac: mac, name: device.displayName) } label: { Image(systemName: "power") }
                    .buttonStyle(RedButtonStyle(prominent: false)).help("Wake-on-LAN: Magic Packet senden")
            }
            Button { copy(device.ip) } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(RedButtonStyle(prominent: false)).help("IP kopieren")
            Button { scanner.repingDevice(device.ip) } label: { Image(systemName: "waveform.path.ecg") }
                .buttonStyle(RedButtonStyle(prominent: false)).help("Erneut pingen")
        }
    }

    private var webURL: URL? {
        if let p = device.upnp.compactMap(\.presentationURL).first, let u = URL(string: p), u.scheme != nil { return u }
        if let h = device.http.first(where: { !$0.tls }) ?? device.http.first {
            return URL(string: "\(h.tls ? "https" : "http")://\(device.ip):\(h.port)/")
        }
        return nil
    }

    private var portsSection: some View {
        section(device.deepScanned ? "Offene Ports (Tiefenscan)" : "Offene Ports", "door.left.hand.open") {
            if !device.portsScanned {
                Text("Noch nicht gescannt").font(.system(size: 12)).foregroundStyle(Theme.dim)
            } else if device.openPorts.isEmpty {
                Text("Keine offenen TCP-Ports gefunden (Firewall aktiv oder Ports geschlossen).").font(.system(size: 12)).foregroundStyle(Theme.dim)
            } else {
                ForEach(device.openPorts) { p in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(p.port)")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.white)
                            .frame(width: 52, height: 22)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.gradient))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.service).font(.system(size: 12, weight: .semibold))
                            if let b = p.banner {
                                Text(b).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Theme.dim).textSelection(.enabled).lineLimit(3)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var webSection: some View {
        section("Web & TLS", "globe") {
            ForEach(device.http) { h in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("\(h.tls ? "https" : "http")://\(device.ip):\(h.port)")
                            .font(.system(size: 11.5, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.redBright)
                        Spacer()
                        if let s = h.status { Pill(text: "HTTP \(s)") }
                    }
                    subrow("Titel", h.title)
                    subrow("Server", h.server)
                    subrow("Powered by", h.poweredBy)
                    subrow("Zertifikat", h.certificate)
                    subrow("Weiterleitung", h.finalURL)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.insetSoft))
            }
        }
    }

    private var servicesSection: some View {
        section("Bonjour-Dienste (\(device.services.count))", "bonjour") {
            ForEach(device.services) { s in
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 3) {
                        subrow("Typ", s.type)
                        subrow("Host", s.hostName)
                        subrow("Port", "\(s.port)")
                        ForEach(s.txt.keys.sorted(), id: \.self) { k in
                            if let v = s.txt[k], !v.isEmpty { subrow(k, v) }
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    HStack {
                        Text(s.typeLabel).font(.system(size: 12, weight: .semibold))
                        Text(s.name).font(.system(size: 11)).foregroundStyle(Theme.dim).lineLimit(1)
                    }
                }
                .tint(Theme.redBright)
            }
        }
    }

    private var upnpSection: some View {
        section("UPnP / DLNA", "point.3.connected.trianglepath.dotted") {
            ForEach(device.upnp, id: \.location) { u in
                VStack(alignment: .leading, spacing: 3) {
                    subrow("Name", u.friendlyName)
                    subrow("Gerätetyp", u.deviceType?.replacingOccurrences(of: "urn:schemas-upnp-org:device:", with: ""))
                    subrow("Beschreibung", u.modelDescription)
                    subrow("Server", u.server)
                    subrow("Admin-URL", u.presentationURL)
                    subrow("XML", u.location)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.insetSoft))
            }
        }
    }

    // MARK: - Bausteine

    private func section<C: View>(_ title: String, _ icon: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title.uppercased(), systemImage: icon)
                .font(.system(size: 10.5, weight: .bold)).tracking(1)
                .foregroundStyle(Theme.redBright)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.stroke))
    }

    @ViewBuilder
    private func row(_ k: String, _ v: String?, mono: Bool = false) -> some View {
        if let v, !v.isEmpty {
            HStack(alignment: .top, spacing: 10) {
                Text(k).font(.system(size: 11.5)).foregroundStyle(Theme.dim).frame(width: 108, alignment: .leading)
                Text(v).font(.system(size: 12, design: mono ? .monospaced : .default)).textSelection(.enabled)
                Spacer(minLength: 0)
            }
            .contextMenu { Button("Kopieren") { copy(v) } }
        }
    }

    @ViewBuilder
    private func subrow(_ k: String, _ v: String?) -> some View {
        if let v, !v.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                Text(k).font(.system(size: 10.5)).foregroundStyle(Theme.faint).frame(width: 82, alignment: .leading)
                Text(v).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Theme.dim).textSelection(.enabled)
                Spacer(minLength: 0)
            }
        }
    }

    private func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }
}
