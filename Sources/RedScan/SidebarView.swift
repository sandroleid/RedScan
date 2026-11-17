import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var scanner: NetScanner
    @EnvironmentObject var history: HistoryStore
    @EnvironmentObject var nav: SelectionState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                tabs
                RadarView(active: scanner.isScanning, blips: scanner.devices.keys.filter { $0 != scanner.network?.ip })
                    .frame(height: 190)
                    .padding(.horizontal, 8)
                scanControls
                if scanner.arpBlocked { permissionHint }
                networkCard
                statsCard
                Spacer(minLength: 0)
            }
            .padding(18)
            .padding(.top, 18)
        }
        .background(
            ZStack {
                Theme.panel
                Theme.glow
            }
        )
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.gradient)
                Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
            }
            .frame(width: 34, height: 34)
            .shadow(color: Theme.red.opacity(0.6), radius: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text("RedScan").font(.system(size: 19, weight: .heavy, design: .rounded))
                Text("Netzwerk-Scanner").font(.system(size: 11)).foregroundStyle(Theme.dim)
            }
        }
    }

    private var tabs: some View {
        HStack(spacing: 6) {
            tabButton(.devices, "Geräte", "square.grid.2x2.fill", badge: scanner.devices.count)
            tabButton(.history, "Verlauf", "clock.arrow.circlepath", badge: history.newInLastScan.count, highlight: !history.newInLastScan.isEmpty)
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.3)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.stroke))
    }

    private func tabButton(_ tab: SelectionState.Tab, _ title: String, _ icon: String, badge: Int, highlight: Bool = false) -> some View {
        let active = nav.tab == tab
        return Button { withAnimation(.snappy) { nav.tab = tab } } label: {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11))
                Text(title).font(.system(size: 12, weight: .semibold))
                if badge > 0 {
                    Text("\(badge)").font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(highlight ? Color.white.opacity(active ? 0.3 : 0) : Color.black.opacity(0.25)))
                        .background(Capsule().fill(highlight && !active ? Theme.red : .clear))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .foregroundStyle(active ? .white : Theme.dim)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(active ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Color.clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var scanControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            if scanner.isScanning {
                Button { scanner.cancel() } label: {
                    Label("Scan abbrechen", systemImage: "stop.fill")
                }
                .buttonStyle(RedButtonStyle(prominent: false))
            } else {
                Button { scanner.start() } label: {
                    Label(scanner.lastScan == nil ? "Netzwerk scannen" : "Erneut scannen", systemImage: "antenna.radiowaves.left.and.right")
                }
                .buttonStyle(RedButtonStyle())
                .keyboardShortcut("r", modifiers: .command)
            }

            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: scanner.progress)
                    .progressViewStyle(.linear)
                    .tint(Theme.red)
                Text(scanner.phase)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(2)
                if let d = scanner.scanDuration, !scanner.isScanning {
                    Text(String(format: "Dauer: %.1f s", d)).font(.system(size: 10)).foregroundStyle(Theme.faint)
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "scope").foregroundStyle(Theme.redBright).font(.system(size: 11))
                TextField(scanner.network?.cidr ?? "z. B. 192.168.1.0/24", text: $scanner.customTarget)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .onSubmit { scanner.refreshNetwork() }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.3)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.stroke))
            .help("Optional: eigenes Ziel als CIDR, z. B. 192.168.0.0/23. Leer = automatisch.")
        }
    }

    private var networkCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("NETZWERK").font(.system(size: 10, weight: .bold)).tracking(1.2).foregroundStyle(Theme.redBright)
                Spacer()
                Button { scanner.refreshNetwork() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).foregroundStyle(Theme.dim).help("Netzwerk neu erkennen")
            }
            if let n = scanner.network {
                kv("Interface", n.interface)
                if let s = n.ssid { kv("WLAN", s) }
                kv("Eigene IP", n.ip, mono: true)
                kv("MAC", n.mac, mono: true)
                kv("Subnetz", "\(n.cidr)", mono: true)
                kv("Maske", n.netmask, mono: true)
                kv("Gateway", n.gateway, mono: true)
                kv("DNS", n.dns.prefix(3).joined(separator: "\n"), mono: true)
                kv("Hosts", "\(n.hosts.count) Adressen")
                HStack(alignment: .top) {
                    Text("Öffentl. IP").font(.system(size: 11)).foregroundStyle(Theme.dim).frame(width: 74, alignment: .leading)
                    if let p = scanner.publicIP {
                        Text(p).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    } else {
                        Button(scanner.loadingPublicIP ? "Lädt …" : "Abrufen") { scanner.fetchPublicIP() }
                            .buttonStyle(.plain).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.redBright)
                    }
                }
                if let note = n.note {
                    Text(note).font(.system(size: 10)).foregroundStyle(Theme.redBright).padding(.top, 2)
                }
            } else {
                Text("Kein aktives Netzwerk").font(.system(size: 12)).foregroundStyle(Theme.dim)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.stroke))
    }

    private var permissionHint: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Zugriff eingeschränkt", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.redBright)
            Text("macOS blendet die ARP-Tabelle aus. Dadurch fehlen MAC-Adressen und Hersteller, und Geräte, die Ping blockieren, werden nicht gefunden. Erlaube RedScan den Zugriff auf das lokale Netzwerk und scanne danach erneut.")
                .font(.system(size: 11)).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
            Button("Einstellungen öffnen") { scanner.openLocalNetworkSettings() }
                .buttonStyle(RedButtonStyle(prominent: false))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.red.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.red.opacity(0.45)))
    }

    private var statsCard: some View {
        HStack(spacing: 8) {
            stat("\(scanner.devices.count)", "Geräte")
            stat("\(scanner.totalOpenPorts)", "Ports")
            stat("\(scanner.totalServices)", "Dienste")
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(Theme.redBright)
                .contentTransition(.numericText())
            Text(label).font(.system(size: 10)).foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.stroke))
    }

    @ViewBuilder
    private func kv(_ k: String, _ v: String?, mono: Bool = false) -> some View {
        if let v, !v.isEmpty {
            HStack(alignment: .top) {
                Text(k).font(.system(size: 11)).foregroundStyle(Theme.dim).frame(width: 74, alignment: .leading)
                Text(v).font(.system(size: 11, design: mono ? .monospaced : .default)).textSelection(.enabled)
                Spacer(minLength: 0)
            }
        }
    }
}
