import SwiftUI
import AppKit

/// Gemeinsame App-Zustände – auch für den AppDelegate erreichbar (Scan-Start ohne Fenster, CI).
@MainActor
enum AppModel {
    static let history = HistoryStore()
    static let scanner = NetScanner(history: history)
    static let nav = SelectionState()
    static let appearance = AppearanceStore()

    /// Wurzelansicht mit allen Umgebungsobjekten (für die Szene und ein ggf. selbst erzeugtes Fenster).
    static func rootView() -> some View {
        RootView()
            .environmentObject(scanner)
            .environmentObject(history)
            .environmentObject(nav)
            .environmentObject(appearance)
    }
}

struct RootView: View {
    @EnvironmentObject var appearance: AppearanceStore

    var body: some View {
        ContentView()
            .frame(minWidth: 1080, minHeight: 680)
            .preferredColorScheme(appearance.mode.colorScheme)
            .foregroundStyle(Theme.text)
            .tint(Theme.red)
            .onAppear { appearance.apply() }
    }
}

@main
struct RedScanApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var scanner = AppModel.scanner
    @ObservedObject private var nav = AppModel.nav

    var body: some Scene {
        WindowGroup("RedScan", id: "main") {
            AppModel.rootView()
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
    private var activity: NSObjectProtocol?
    private var fallbackWindow: NSWindow?

    func applicationWillFinishLaunching(_ notification: Notification) {
        setvbuf(stdout, nil, _IOLBF, 0) // Ausgaben sofort sichtbar (CI-Log)
        // Für CI: wirksame Darstellung ausgeben und beenden (prüft Speicherung und --theme)
        if CommandLine.arguments.contains("--print-appearance") {
            print("appearance=\(Appearance.effectiveAtLaunch.rawValue) stored=\(UserDefaults.standard.string(forKey: Appearance.defaultsKey) ?? "-")")
            exit(0)
        }
        NSApp.appearance = Appearance.effectiveAtLaunch.nsAppearance
        // Autoscan/CI: kein App Nap, sonst laufen Timer im Hintergrund stark verzögert
        if CICapture.enabled || CommandLine.arguments.contains("--autoscan") {
            activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: "RedScan Autoscan/CI")
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        raiseFileLimit()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let scanner = AppModel.scanner
        let autoscan = CommandLine.arguments.contains("--autoscan")
        // Scan unabhängig davon starten, ob schon ein Fenster da ist
        if autoscan {
            Task { @MainActor in scanner.start() }
        }
        guard CICapture.enabled else { return }
        print("Gestartet, Darstellung \(Appearance.effectiveAtLaunch.rawValue), Fenster: \(NSApp.windows.count)")
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            self.ensureWindow()
            // Warten, bis der Scan fertig ist (ohne --autoscan sofort), dann Bilder vorbereiten
            while autoscan && (scanner.isScanning || scanner.lastScan == nil) {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            self.ensureWindow()
            CICapture.run(scanner: scanner, selection: AppModel.nav, appearance: AppModel.appearance)
        }
    }

    /// Falls SwiftUI (noch) kein Fenster geöffnet hat, selbst eins erzeugen.
    @MainActor
    private func ensureWindow() {
        if let w = CICapture.mainWindow {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1400, height: 860),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.title = "RedScan"
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: AppModel.rootView())
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        fallbackWindow = w
        print("Kein Fenster von SwiftUI – Fenster selbst geöffnet")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct ContentView: View {
    @EnvironmentObject var scanner: NetScanner
    @EnvironmentObject var sel: SelectionState

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
            if CICapture.enabled { print("Hauptansicht erschienen") }
        }
        .onChange(of: scanner.isScanning) { _, scanning in
            if scanning, let s = sel.ip, scanner.devices[s] == nil { sel.ip = nil }
        }
    }
}

/// Für CI: `--ci-capture` bereitet nach dem Scan das Fenster für Screenshots vor und meldet im Log,
/// wann `screencapture -l <Fenster-ID>` ein Bild machen kann (oben, dann Seitenleiste ans Ende gescrollt).
@MainActor
enum CICapture {
    static var enabled: Bool { CommandLine.arguments.contains("--ci-capture") }
    private static var done = false

    /// `--switch-appearance light|dark`: vorher live umschalten (wie ein Klick im Umschalter, wird gespeichert).
    static var switchTo: Appearance? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--switch-appearance"), i + 1 < args.count else { return nil }
        return Appearance(rawValue: args[i + 1].lowercased())
    }

    static var mainWindow: NSWindow? {
        NSApp.windows.first { $0.isVisible && $0.contentView != nil && !($0 is NSPanel) && $0.frame.width > 600 }
    }

    static func run(scanner: NetScanner, selection: SelectionState, appearance: AppearanceStore) {
        guard enabled, !done else { return }
        done = true
        if let m = switchTo {
            appearance.select(m)
            print("Darstellung live umgeschaltet: \(m.rawValue)")
        }
        // Detailansicht mit zeigen (Gateway bzw. erstes Gerät) und Fenster so groß wie möglich
        if selection.ip == nil {
            selection.ip = scanner.sortedDevices.first(where: \.isGateway)?.ip ?? scanner.sortedDevices.first?.ip
        }
        let win = mainWindow
        if let win, let screen = win.screen ?? NSScreen.main {
            // Der CI-Bildschirm ist klein (1024×768): Breite so wählen, dass Liste und Detailansicht Platz haben.
            // screencapture -l nimmt auch den Teil des Fensters auf, der über den Bildschirmrand ragt.
            let v = screen.visibleFrame
            win.setFrame(NSRect(x: v.minX, y: v.minY, width: max(v.width, 1440), height: v.height), display: true)
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            print("Fenster-ID \(win?.windowNumber ?? 0) Größe \(win.map { "\(Int($0.frame.width))x\(Int($0.frame.height))" } ?? "-") Darstellung \(win?.effectiveAppearance.name.rawValue ?? "-")")
            print("BEREIT-OBEN")
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            NotificationCenter.default.post(name: .redScanScrollSidebarToEnd, object: nil)
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            print("BEREIT-UNTEN")
        }
    }
}

extension Notification.Name {
    static let redScanScrollSidebarToEnd = Notification.Name("RedScanScrollSidebarToEnd")
}
