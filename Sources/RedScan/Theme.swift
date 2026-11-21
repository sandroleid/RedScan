import SwiftUI
import AppKit

// MARK: - Darstellung (Hell/Dunkel)

enum Appearance: String, CaseIterable {
    case dark, light

    static let defaultsKey = "appearance"

    /// `--theme light|dark` überschreibt die gespeicherte Wahl nur für diesen Start.
    static var commandLineOverride: Appearance? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--theme"), i + 1 < args.count else { return nil }
        return Appearance(rawValue: args[i + 1].lowercased())
    }

    /// Gespeicherte Wahl (UserDefaults `appearance`), Standard: dunkel.
    static var stored: Appearance {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(Appearance.init(rawValue:)) ?? .dark
    }

    static var effectiveAtLaunch: Appearance { commandLineOverride ?? stored }

    var colorScheme: ColorScheme { self == .dark ? .dark : .light }
    var nsAppearance: NSAppearance? { NSAppearance(named: self == .dark ? .darkAqua : .aqua) }
}

@MainActor
final class AppearanceStore: ObservableObject {
    @Published private(set) var mode: Appearance = Appearance.effectiveAtLaunch

    /// Vom Nutzer gewählt: sofort anwenden und speichern.
    func select(_ m: Appearance) {
        UserDefaults.standard.set(m.rawValue, forKey: Appearance.defaultsKey)
        guard m != mode else { return }
        mode = m
        apply()
    }

    /// Fenster, Titelleiste und App-Dialoge (Speichern-Panel, Alerts) folgen dem Modus.
    func apply() {
        NSApp?.appearance = mode.nsAppearance
    }
}

// MARK: - Farb-Tokens

enum Theme {
    /// Dunkle Primärtextfarbe des Hellmodus (#1A0F11).
    private static let ink = NSColor(srgbRed: 0x1A / 255.0, green: 0x0F / 255.0, blue: 0x11 / 255.0, alpha: 1)
    private static let redNS = NSColor(srgbRed: 0.91, green: 0.13, blue: 0.19, alpha: 1)

    private static func hex(_ v: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    /// Farbe, die sich nach der aktuellen Darstellung (Hell/Dunkel) richtet.
    static func dynamic(dark: NSColor, light: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .aqua ? light : dark
        })
    }

    // Flächen
    static let bg = dynamic(dark: rgb(0.050, 0.030, 0.036), light: hex(0xF6F1F2))
    static let panel = dynamic(dark: rgb(0.078, 0.044, 0.052), light: hex(0xFBF7F7))
    static let card = dynamic(dark: rgb(0.115, 0.062, 0.072), light: hex(0xFFFFFF))
    static let cardHi = dynamic(dark: rgb(0.165, 0.074, 0.086), light: hex(0xF7E6E8))

    // Text
    static let text = dynamic(dark: rgb(1, 1, 1), light: ink)
    static let dim = dynamic(dark: rgb(1, 1, 1, 0.55), light: ink.withAlphaComponent(0.62))
    static let faint = dynamic(dark: rgb(1, 1, 1, 0.32), light: ink.withAlphaComponent(0.40))

    // Linien & Vertiefungen
    static let stroke = dynamic(dark: rgb(1, 1, 1, 0.07), light: ink.withAlphaComponent(0.10))
    /// Tab-Leiste, Eingabefeld
    static let inset = dynamic(dark: rgb(0, 0, 0, 0.30), light: ink.withAlphaComponent(0.05))
    /// Etwas schwächere Vertiefung (Info-Kästen in der Detailansicht, Zähler-Badges)
    static let insetSoft = dynamic(dark: rgb(0, 0, 0, 0.25), light: ink.withAlphaComponent(0.05))
    /// Rand der Ghost-Buttons
    static let ghostStroke = dynamic(dark: rgb(1, 1, 1, 0.05), light: ink.withAlphaComponent(0.06))

    // Rot
    static let red = Color(nsColor: redNS)
    static let redBright = dynamic(dark: rgb(1.0, 0.34, 0.38), light: hex(0xC8102E))
    static let redDeep = Color(red: 0.42, green: 0.03, blue: 0.07)
    /// Kopf der Detailansicht (Verlauf Rot → Karte)
    static let headerTint = dynamic(dark: redNS.withAlphaComponent(0.35), light: redNS.withAlphaComponent(0.16))

    /// Rote Tönung (Ghost-Button, Pills, Hinweis-Box). Im Hellmodus etwa 10 % statt 13–15 %.
    static func tint(_ darkOpacity: CGFloat) -> Color {
        dynamic(dark: redNS.withAlphaComponent(darkOpacity), light: redNS.withAlphaComponent(darkOpacity * 0.72))
    }

    /// Roter Schatten/Glow – im Hellmodus halb so stark.
    static func shadow(_ darkOpacity: CGFloat) -> Color {
        dynamic(dark: redNS.withAlphaComponent(darkOpacity), light: redNS.withAlphaComponent(darkOpacity / 2))
    }

    /// Verlauf bleibt in beiden Modi die dunkle Variante, damit Buttons und Icons identisch aussehen.
    static let gradient = LinearGradient(colors: [Color(red: 1.0, green: 0.34, blue: 0.38), red, redDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let glow = RadialGradient(
        colors: [dynamic(dark: redNS.withAlphaComponent(0.35), light: redNS.withAlphaComponent(0.12)), .clear],
        center: .top, startRadius: 0, endRadius: 420)
}

struct Pill: View {
    let text: String
    var icon: String? = nil
    var strong = false

    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.system(size: 9, weight: .bold)) }
            Text(text).font(.system(size: 10.5, weight: .semibold))
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .foregroundStyle(strong ? Color.white : Theme.redBright)
        .background(Capsule().fill(strong ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Theme.tint(0.14))))
    }
}

struct KindIcon: View {
    let kind: DeviceKind
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(kind == .unknown ? AnyShapeStyle(Theme.tint(0.15)) : AnyShapeStyle(Theme.gradient))
            Image(systemName: kind.symbol)
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(kind == .unknown ? Theme.redBright : Color.white)
        }
        .frame(width: size, height: size)
        .shadow(color: kind == .unknown ? .clear : Theme.shadow(0.45), radius: size * 0.2, y: size * 0.06)
    }
}

struct RedButtonStyle: ButtonStyle {
    var prominent = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 14).padding(.vertical, 9)
            .frame(maxWidth: prominent ? .infinity : nil)
            .foregroundStyle(prominent ? Color.white : Theme.redBright)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(prominent ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Theme.tint(0.13)))
            )
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(prominent ? Color.white.opacity(0.18) : Theme.ghostStroke))
            .shadow(color: prominent ? Theme.shadow(0.5) : .clear, radius: 10, y: 3)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// Animiertes Radar mit Blips für gefundene Geräte.
struct RadarView: View {
    var active: Bool
    var blips: [String]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: !active)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let angle = active ? (t.truncatingRemainder(dividingBy: 2.4) / 2.4) * 360 : 0
            GeometryReader { geo in
                let s = min(geo.size.width, geo.size.height)
                ZStack {
                    Circle().fill(RadialGradient(colors: [Theme.red.opacity(0.18), Theme.bg.opacity(0.2)], center: .center, startRadius: 0, endRadius: s / 2))
                    ForEach(1..<5) { i in
                        Circle().stroke(Theme.red.opacity(0.22), lineWidth: 1).frame(width: s * CGFloat(i) / 4, height: s * CGFloat(i) / 4)
                    }
                    Rectangle().fill(Theme.red.opacity(0.15)).frame(width: 1, height: s)
                    Rectangle().fill(Theme.red.opacity(0.15)).frame(width: s, height: 1)
                    if active {
                        Circle()
                            .fill(AngularGradient(colors: [Theme.red.opacity(0), Theme.red.opacity(0), Theme.redBright.opacity(0.55)], center: .center, startAngle: .degrees(0), endAngle: .degrees(360)))
                            .rotationEffect(.degrees(angle))
                    }
                    ForEach(blips, id: \.self) { ip in
                        let pos = Self.position(for: ip, size: s)
                        Circle()
                            .fill(Theme.redBright)
                            .frame(width: 6, height: 6)
                            .shadow(color: Theme.redBright, radius: 4)
                            .offset(x: pos.x, y: pos.y)
                    }
                    Circle().fill(Color.white).frame(width: 5, height: 5).shadow(color: Theme.red, radius: 4)
                }
                .frame(width: s, height: s)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
        }
    }

    static func position(for ip: String, size: CGFloat) -> CGPoint {
        let n = Double(ip.split(separator: ".").last.flatMap { Int($0) } ?? 1)
        let a = n * 2.399963 // goldener Winkel
        let r = (0.22 + (n.truncatingRemainder(dividingBy: 11)) / 15) * Double(size) / 2
        return CGPoint(x: cos(a) * r, y: sin(a) * r)
    }
}
