import SwiftUI
import AppKit

@main
struct RedScanApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var history: HistoryStore
    @StateObject private var scanner: NetScanner
    @StateObject private var nav = SelectionState()
    @StateObject private var appearance = AppearanceStore()

    init() {
        let h = HistoryStore()
        _history = StateObject(wrappedValue: h)
        _scanner = StateObject(wrappedValue: NetScanner(history: h))
    }

    var body: some Scene {
        WindowGroup("RedScan") {
            ContentView()
                .environmentObject(scanner)
                .environmentObject(history)
                .environmentObject(nav)
                .environmentObject(appearance)
                .frame(minWidth: 1080, minHeight: 680)
                .preferredColorScheme(appearance.mode.colorScheme)
                .foregroundStyle(Theme.text)
                .tint(Theme.red)
                .onAppear { appearance.apply() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1400, height: 860)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Scan") {
                Button("Netzwerk scannen") { scanner.start() }.keyboardShortcut("r")
                Button("Abbrechen") { scanner.cancel() }.keyboardShortcut(".")
                Divider()
                Button("Geräte") { nav.tab = .devices }.keyboardShortcut("1")
                Button("Verlauf") { nav.tab = .history }.keyboardShortcut("2")
                Divider()
                Button("Als JSON exportieren …") { scanner.exportJSON() }.keyboardShortcut("e")
                Button("Als CSV exportieren …") { scanner.exportCSV() }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        setvbuf(stdout, nil, _IOLBF, 0) // Ausgaben sofort sichtbar (CI-Log)
        // Für CI: wirksame Darstellung ausgeben und beenden (prüft Speicherung und --theme)
        if CommandLine.arguments.contains("--print-appearance") {
            print("appearance=\(Appearance.effectiveAtLaunch.rawValue) stored=\(UserDefaults.standard.string(forKey: Appearance.defaultsKey) ?? "-")")
            exit(0)
        }
        NSApp.appearance = Appearance.effectiveAtLaunch.nsAppearance
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        raiseFileLimit()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct ContentView: View {
    @EnvironmentObject var scanner: NetScanner
    @EnvironmentObject var sel: SelectionState
    @EnvironmentObject var appearance: AppearanceStore

    var body: some View {
        HStack(spacing: 0) {
            SidebarView().frame(width: 290)
            Rectangle().fill(Theme.stroke).frame(width: 1)
            switch sel.tab {
            case .devices:
                DevicesView(selection: $sel.ip)
                if let ip = sel.ip, let d = scanner.devices[ip] {
                    Rectangle().fill(Theme.stroke).frame(width: 1)
                    DetailView(device: d) { withAnimation(.snappy) { sel.ip = nil } }
                        .frame(width: 400)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            case .history:
                HistoryView()
            }
        }
        .background(Theme.bg)
        .ignoresSafeArea()
        .overlay(alignment: .bottom) {
            if let t = scanner.toast {
                Label(t, systemImage: "power")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Capsule().fill(Theme.gradient))
                    .shadow(color: Theme.shadow(0.5), radius: 14, y: 4)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: scanner.toast)
        .onAppear {
            if CommandLine.arguments.contains("--autoscan") {
                scanner.start()
            } else if Snapshot.path != nil {
                Task { @MainActor in try? await Task.sleep(nanoseconds: 2_000_000_000); Snapshot.capture(scanner: scanner, selection: sel, appearance: appearance) }
            }
        }
        .onChange(of: scanner.isScanning) { _, scanning in
            if scanning, let s = sel.ip, scanner.devices[s] == nil { sel.ip = nil }
            if !scanning, scanner.lastScan != nil { Snapshot.capture(scanner: scanner, selection: sel, appearance: appearance) }
        }
    }
}

/// Für CI: `--snapshot <png>` speichert nach dem Scan ein Bild des Hauptfensters (ohne Bildschirmaufnahme-Recht).
@MainActor
enum Snapshot {
    static var path: String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
    private static var done = false

    /// `--switch-appearance light|dark`: vor dem Bild live umschalten (wie ein Klick im Umschalter, wird gespeichert).
    static var switchTo: Appearance? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--switch-appearance"), i + 1 < args.count else { return nil }
        return Appearance(rawValue: args[i + 1].lowercased())
    }

    static func capture(scanner: NetScanner, selection: SelectionState, appearance: AppearanceStore) {
        guard let path, !done else { return }
        done = true
        if let m = switchTo {
            appearance.select(m)
            print("Darstellung live umgeschaltet: \(m.rawValue)")
        }
        // Detailansicht mit zeigen (Gateway bzw. erstes Gerät), Fenster groß machen, Seitenleiste ans Ende scrollen
        if selection.ip == nil {
            selection.ip = scanner.sortedDevices.first(where: \.isGateway)?.ip ?? scanner.sortedDevices.first?.ip
        }
        if let win = mainWindow, let screen = win.screen ?? NSScreen.main {
            win.setFrame(screen.visibleFrame, display: true)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            NotificationCenter.default.post(name: .redScanScrollSidebarToEnd, object: nil)
        }
        Task { @MainActor in try? await Task.sleep(nanoseconds: 3_000_000_000); write(to: path) }
    }

    private static var mainWindow: NSWindow? {
        NSApp.windows.first { $0.isVisible && $0.contentView != nil && !($0 is NSPanel) }
    }

    static func write(to path: String) {
        guard let win = mainWindow, let view = win.contentView?.superview ?? win.contentView else {
            print("Snapshot: kein Fenster gefunden"); return
        }
        let rect = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: rect) else { print("Snapshot: kein Bitmap"); return }
        view.cacheDisplay(in: rect, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { print("Snapshot: PNG fehlgeschlagen"); return }
        do {
            try data.write(to: URL(fileURLWithPath: path))
            print("Snapshot gespeichert: \(path) (\(Int(rect.width))x\(Int(rect.height)), Darstellung \(win.effectiveAppearance.name.rawValue))")
        } catch {
            print("Snapshot: \(error)")
        }
    }
}

extension Notification.Name {
    static let redScanScrollSidebarToEnd = Notification.Name("RedScanScrollSidebarToEnd")
}
