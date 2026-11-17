import SwiftUI

final class HistoryUIState: ObservableObject {
    enum Filter: String, CaseIterable { case all = "Alle", online = "Online", offline = "Offline" }
    @Published var filter: Filter = .all
    @Published var search = ""
    @Published var expanded: UUID?
    @Published var confirmClear = false
}

struct HistoryView: View {
    @EnvironmentObject var scanner: NetScanner
    @EnvironmentObject var history: HistoryStore
    @StateObject private var ui = HistoryUIState()

    private var list: [KnownDevice] {
        var l = history.sortedKnown
        switch ui.filter {
        case .all: break
        case .online: l = l.filter { scanner.isOnline($0) }
        case .offline: l = l.filter { !scanner.isOnline($0) }
        }
        let q = ui.search.lowercased().trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            l = l.filter { "\($0.name) \($0.lastIP) \($0.mac ?? "") \($0.vendor ?? "") \($0.kind.label)".lowercased().contains(q) }
        }
        return l
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
                toolbar
                if history.known.isEmpty {
                    empty
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(list) { k in KnownRow(device: k, online: scanner.isOnline(k), isNew: history.newInLastScan.contains(k.key)) }
                        }
                        .padding(20)
                    }
                }
            }
            Rectangle().fill(Theme.stroke).frame(width: 1)
            timeline.frame(width: 330)
        }
        .background(Theme.bg)
        .alert("Gesamten Verlauf löschen?", isPresented: $ui.confirmClear) {
            Button("Löschen", role: .destructive) { history.clear() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Alle bekannten Geräte und gespeicherten Scans werden entfernt.")
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Verlauf").font(.system(size: 24, weight: .heavy, design: .rounded))
                Text("\(history.known.count) bekannte Geräte · \(history.scans.count) Scans")
                    .font(.system(size: 11)).foregroundStyle(Theme.dim)
            }
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.dim)
                TextField("Suchen …", text: $ui.search).textFieldStyle(.plain)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .frame(width: 200)
            .background(RoundedRectangle(cornerRadius: 9).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.stroke))

            Picker("", selection: $ui.filter) {
                ForEach(HistoryUIState.Filter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 200)

            Button { ui.confirmClear = true } label: { Image(systemName: "trash") }
                .buttonStyle(.plain).foregroundStyle(Theme.dim).help("Verlauf löschen")
                .disabled(history.known.isEmpty)
        }
        .padding(.horizontal, 20).padding(.top, 26).padding(.bottom, 12)
    }

    private var empty: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "clock.arrow.circlepath").font(.system(size: 46, weight: .semibold)).foregroundStyle(Theme.gradient)
            Text("Noch kein Verlauf").font(.system(size: 18, weight: .bold, design: .rounded))
            Text("Nach jedem abgeschlossenen Scan werden die Geräte hier gespeichert.\nSo siehst du, wer neu dazugekommen oder verschwunden ist.")
                .multilineTextAlignment(.center).font(.system(size: 12)).foregroundStyle(Theme.dim)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Zeitleiste

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SCANS").font(.system(size: 10.5, weight: .bold)).tracking(1.2).foregroundStyle(Theme.redBright)
                .padding(.horizontal, 18).padding(.top, 34).padding(.bottom, 10)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(history.scans) { s in scanCard(s) }
                }
                .padding(.horizontal, 14).padding(.bottom, 14)
            }
        }
        .background(Theme.panel)
    }

    private func scanCard(_ s: ScanRecord) -> some View {
        let open = ui.expanded == s.id
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(s.date.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 12.5, weight: .semibold))
                Spacer()
                Text("\(s.deviceKeys.count)").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(Theme.redBright)
                Image(systemName: "desktopcomputer").font(.system(size: 10)).foregroundStyle(Theme.dim)
            }
            Text([s.ssid, s.network, s.duration.map { String(format: "%.0f s", $0) }].compactMap { $0 }.joined(separator: " · "))
                .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Theme.faint)
            if !s.newKeys.isEmpty || !s.goneKeys.isEmpty {
                HStack(spacing: 5) {
                    if !s.newKeys.isEmpty { Pill(text: "+\(s.newKeys.count) neu", icon: "plus", strong: true) }
                    if !s.goneKeys.isEmpty { Pill(text: "−\(s.goneKeys.count) weg", icon: "minus") }
                    Spacer()
                    Image(systemName: open ? "chevron.up" : "chevron.down").font(.system(size: 10)).foregroundStyle(Theme.dim)
                }
            }
            if open {
                ForEach(s.newKeys, id: \.self) { k in changeRow(k, added: true) }
                ForEach(s.goneKeys, id: \.self) { k in changeRow(k, added: false) }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(open ? Theme.cardHi : Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.stroke))
        .contentShape(Rectangle())
        .onTapGesture {
            guard !s.newKeys.isEmpty || !s.goneKeys.isEmpty else { return }
            withAnimation(.snappy) { ui.expanded = open ? nil : s.id }
        }
    }

    private func changeRow(_ key: String, added: Bool) -> some View {
        let k = history.known[key]
        return HStack(spacing: 6) {
            Image(systemName: added ? "plus.circle.fill" : "minus.circle.fill")
                .foregroundStyle(added ? Theme.redBright : Theme.dim).font(.system(size: 11))
            Text(k?.name ?? key).font(.system(size: 11)).lineLimit(1)
            Spacer()
            Text(k?.lastIP ?? "").font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.faint)
        }
    }
}

struct KnownRow: View {
    @EnvironmentObject var scanner: NetScanner
    @EnvironmentObject var history: HistoryStore
    let device: KnownDevice
    let online: Bool
    let isNew: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                KindIcon(kind: device.kind, size: 32).opacity(online ? 1 : 0.45)
                Circle().fill(online ? Color.green : Color.gray)
                    .frame(width: 9, height: 9)
                    .overlay(Circle().stroke(Theme.card, lineWidth: 2))
                    .offset(x: 2, y: 2)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(device.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    if isNew { Pill(text: "NEU", strong: true) }
                }
                Text([device.kind.label, device.vendor].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 10.5)).foregroundStyle(Theme.dim).lineLimit(1)
            }
            .frame(width: 240, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.lastIP).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.redBright)
                Text(device.mac ?? "keine MAC").font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Theme.faint)
            }
            .frame(width: 140, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(online ? "Online" : "Zuletzt \(device.lastSeen.formatted(.relative(presentation: .named)))")
                    .font(.system(size: 11, weight: online ? .semibold : .regular))
                    .foregroundStyle(online ? Color.green : Theme.dim)
                Text("Zuerst \(device.firstSeen.formatted(date: .abbreviated, time: .omitted)) · \(device.seenCount)× gesehen")
                    .font(.system(size: 10)).foregroundStyle(Theme.faint)
            }
            Spacer(minLength: 0)
            if let mac = device.mac {
                Button { scanner.wake(mac: mac, name: device.name) } label: {
                    Label("Aufwecken", systemImage: "power")
                }
                .buttonStyle(RedButtonStyle(prominent: !online))
                .help("Wake-on-LAN: Magic Packet an \(mac) senden")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(isNew ? Theme.red : Theme.stroke))
        .contextMenu {
            if let mac = device.mac {
                Button("MAC kopieren") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(mac, forType: .string) }
            }
            Button("Aus Verlauf entfernen", role: .destructive) { history.remove(device.key) }
        }
    }
}
