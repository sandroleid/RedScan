import SwiftUI

enum SortMode: String, CaseIterable { case ip = "IP-Adresse", name = "Name", vendor = "Hersteller", kind = "Typ", ports = "Offene Ports" }

struct DevicesView: View {
    @EnvironmentObject var scanner: NetScanner
    @EnvironmentObject var history: HistoryStore
    @Binding var selection: String?
    @StateObject private var ui = DevicesUIState()

    private var filtered: [Device] {
        var list = scanner.sortedDevices
        if let k = ui.kindFilter { list = list.filter { $0.kind == k } }
        let q = ui.search.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty { list = list.filter { $0.searchBlob.contains(q) || $0.displayName.lowercased().contains(q) } }
        switch ui.sort {
        case .ip: break
        case .name: list.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        case .vendor: list.sort { ($0.vendor ?? "~") < ($1.vendor ?? "~") }
        case .kind: list.sort { $0.kind.label < $1.kind.label }
        case .ports: list.sort { $0.openPorts.count > $1.openPorts.count }
        }
        return list
    }

    private var kindCounts: [(DeviceKind, Int)] {
        Dictionary(grouping: scanner.devices.values, by: \.kind).map { ($0.key, $0.value.count) }.sorted { $0.1 > $1.1 }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if !kindCounts.isEmpty { filterChips }
            if scanner.devices.isEmpty {
                emptyState
            } else if filtered.isEmpty {
                Spacer()
                Text("Keine Treffer für „\(ui.search)“").foregroundStyle(Theme.dim)
                Spacer()
            } else {
                ScrollView {
                    if ui.listMode {
                        LazyVStack(spacing: 6) {
                            ForEach(filtered) { d in
                                DeviceRow(device: d, selected: selection == d.ip, busy: scanner.busyDevices.contains(d.ip), isNew: history.newInLastScan.contains(HistoryStore.key(for: d)))
                                    .onTapGesture { withAnimation(.snappy) { selection = d.ip } }
                            }
                        }
                        .padding(20)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 230, maximum: 320), spacing: 14)], spacing: 14) {
                            ForEach(filtered) { d in
                                DeviceCard(device: d, selected: selection == d.ip, busy: scanner.busyDevices.contains(d.ip), isNew: history.newInLastScan.contains(HistoryStore.key(for: d)))
                                    .onTapGesture { withAnimation(.snappy) { selection = d.ip } }
                            }
                        }
                        .padding(20)
                    }
                }
                .animation(.snappy, value: filtered.map(\.ip))
            }
        }
        .background(Theme.bg)
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Geräte").font(.system(size: 24, weight: .heavy, design: .rounded))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(Theme.dim)
            }
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.dim)
                TextField("Suchen: IP, Name, Hersteller, Port …", text: $ui.search).textFieldStyle(.plain)
                if !ui.search.isEmpty {
                    Button { ui.search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(Theme.dim)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .frame(width: 280)
            .background(RoundedRectangle(cornerRadius: 9).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.stroke))

            Menu {
                Picker("Sortieren", selection: $ui.sort) { ForEach(SortMode.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            } label: { Image(systemName: "arrow.up.arrow.down") }
                .menuStyle(.borderlessButton).frame(width: 30).help("Sortieren")

            Picker("", selection: $ui.listMode) {
                Image(systemName: "square.grid.2x2").tag(false)
                Image(systemName: "list.bullet").tag(true)
            }
            .pickerStyle(.segmented).frame(width: 80).labelsHidden()

            Menu {
                Button("Als JSON exportieren …") { scanner.exportJSON() }
                Button("Als CSV exportieren …") { scanner.exportCSV() }
            } label: { Image(systemName: "square.and.arrow.up") }
                .menuStyle(.borderlessButton).frame(width: 30).disabled(scanner.devices.isEmpty).help("Exportieren")
        }
        .padding(.horizontal, 20)
        .padding(.top, 26)
        .padding(.bottom, 12)
    }

    private var subtitle: String {
        if scanner.devices.isEmpty { return scanner.isScanning ? "Suche läuft …" : "Noch kein Scan durchgeführt" }
        let base = "\(scanner.devices.count) Geräte · \(scanner.network?.cidr ?? "")"
        if let t = scanner.lastScan, !scanner.isScanning { return base + " · zuletzt " + t.formatted(date: .omitted, time: .shortened) }
        return base
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(nil, "Alle", scanner.devices.count, "circle.grid.3x3.fill")
                ForEach(kindCounts, id: \.0) { k, c in chip(k, k.label, c, k.symbol) }
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 4)
    }

    private func chip(_ kind: DeviceKind?, _ label: String, _ count: Int, _ icon: String) -> some View {
        let active = ui.kindFilter == kind
        return Button { withAnimation(.snappy) { ui.kindFilter = kind } } label: {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10))
                Text(label).font(.system(size: 11.5, weight: .semibold))
                Text("\(count)").font(.system(size: 10.5, weight: .bold)).opacity(0.75)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .foregroundStyle(active ? .white : Theme.dim)
            .background(Capsule().fill(active ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Theme.card)))
            .overlay(Capsule().stroke(active ? Color.clear : Theme.stroke))
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer()
            ZStack {
                Circle().fill(Theme.red.opacity(0.08)).frame(width: 170, height: 170)
                Circle().stroke(Theme.red.opacity(0.25), lineWidth: 1).frame(width: 120, height: 120)
                Image(systemName: scanner.isScanning ? "dot.radiowaves.left.and.right" : "wifi.router")
                    .font(.system(size: 50, weight: .semibold))
                    .foregroundStyle(Theme.gradient)
                    .symbolEffect(.variableColor.iterative, isActive: scanner.isScanning)
            }
            Text(scanner.isScanning ? "Netzwerk wird durchsucht …" : "Bereit zum Scannen")
                .font(.system(size: 20, weight: .bold, design: .rounded))
            Text("RedScan findet alle Geräte in deinem Netzwerk und sammelt\nHersteller, Namen, offene Ports, Dienste und mehr.")
                .multilineTextAlignment(.center).font(.system(size: 13)).foregroundStyle(Theme.dim)
            if !scanner.isScanning {
                Button { scanner.start() } label: { Label("Scan starten", systemImage: "play.fill") }
                    .buttonStyle(RedButtonStyle()).frame(width: 200)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

struct DeviceCard: View {
    let device: Device
    let selected: Bool
    let busy: Bool
    var isNew = false
    @StateObject private var hoverState = HoverState()
    private var hover: Bool { hoverState.on }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                KindIcon(kind: device.kind, size: 42)
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    if device.isGateway { Pill(text: "Gateway", icon: "arrow.triangle.branch", strong: true) }
                    if device.isSelf { Pill(text: "Du", icon: "person.fill", strong: true) }
                    if isNew { Pill(text: "NEU", icon: "sparkles", strong: true) }
                    if busy { ProgressView().controlSize(.small) }
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(device.displayName).font(.system(size: 14, weight: .bold)).lineLimit(1)
                Text(device.ip).font(.system(size: 12.5, weight: .medium, design: .monospaced)).foregroundStyle(Theme.redBright)
                Text(device.vendor ?? (device.randomizedMAC ? "Private (zufällige) MAC" : "Hersteller unbekannt"))
                    .font(.system(size: 11)).foregroundStyle(Theme.dim).lineLimit(1)
            }
            HStack(spacing: 5) {
                Pill(text: device.kind.label)
                if !device.openPorts.isEmpty { Pill(text: "\(device.openPorts.count)", icon: "door.left.hand.open") }
                if !device.services.isEmpty { Pill(text: "\(device.services.count)", icon: "bonjour") }
                Spacer(minLength: 0)
                if let l = device.latencyMs, !device.isSelf {
                    Text(l < 1 ? "<1 ms" : "\(Int(l.rounded())) ms").font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.faint)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(selected || hover ? Theme.cardHi : Theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(selected ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Theme.stroke), lineWidth: selected ? 1.6 : 1)
        )
        .shadow(color: selected ? Theme.red.opacity(0.35) : .clear, radius: 14, y: 4)
        .contentShape(Rectangle())
        .onHover { hoverState.on = $0 }
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }
}

struct DeviceRow: View {
    let device: Device
    let selected: Bool
    let busy: Bool
    var isNew = false

    var body: some View {
        HStack(spacing: 12) {
            KindIcon(kind: device.kind, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(device.displayName).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(device.kind.label).font(.system(size: 10.5)).foregroundStyle(Theme.dim)
            }
            .frame(width: 210, alignment: .leading)
            Text(device.ip).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.redBright).frame(width: 110, alignment: .leading)
            Text(device.mac ?? "–").font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.dim).frame(width: 130, alignment: .leading)
            Text(device.vendor ?? "–").font(.system(size: 11.5)).foregroundStyle(Theme.dim).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            Text(device.openPorts.prefix(6).map { "\($0.port)" }.joined(separator: " "))
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.faint).lineLimit(1).frame(width: 150, alignment: .leading)
            if busy { ProgressView().controlSize(.small) }
            if device.isGateway { Pill(text: "Gateway", strong: true) }
            if device.isSelf { Pill(text: "Du", strong: true) }
            if isNew { Pill(text: "NEU", strong: true) }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(selected ? Theme.cardHi : Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(selected ? Theme.red : Theme.stroke))
        .contentShape(Rectangle())
    }
}

/// Ersatz für @State (das SwiftUI-Makro-Plugin fehlt ohne volles Xcode).
final class DevicesUIState: ObservableObject {
    @Published var search = ""
    @Published var kindFilter: DeviceKind?
    @Published var listMode = false
    @Published var sort: SortMode = .ip
}

final class HoverState: ObservableObject {
    @Published var on = false
}

final class SelectionState: ObservableObject {
    enum Tab { case devices, history }
    @Published var ip: String?
    @Published var tab: Tab = .devices
}
