import SwiftUI
import AppKit

@main
struct RedScanApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var history: HistoryStore
    @StateObject private var scanner: NetScanner
    @StateObject private var nav = SelectionState()

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
                .frame(minWidth: 1080, minHeight: 680)
                .preferredColorScheme(.dark)
                .tint(Theme.red)
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
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Capsule().fill(Theme.gradient))
                    .shadow(color: Theme.red.opacity(0.5), radius: 14, y: 4)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: scanner.toast)
        .onAppear {
            if CommandLine.arguments.contains("--autoscan") { scanner.start() }
        }
        .onChange(of: scanner.isScanning) { _, scanning in
            if scanning, let s = sel.ip, scanner.devices[s] == nil { sel.ip = nil }
        }
    }
}
