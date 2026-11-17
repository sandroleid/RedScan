import SwiftUI

enum Theme {
    static let bg = Color(red: 0.050, green: 0.030, blue: 0.036)
    static let panel = Color(red: 0.078, green: 0.044, blue: 0.052)
    static let card = Color(red: 0.115, green: 0.062, blue: 0.072)
    static let cardHi = Color(red: 0.165, green: 0.074, blue: 0.086)
    static let red = Color(red: 0.91, green: 0.13, blue: 0.19)
    static let redBright = Color(red: 1.0, green: 0.34, blue: 0.38)
    static let redDeep = Color(red: 0.42, green: 0.03, blue: 0.07)
    static let dim = Color.white.opacity(0.55)
    static let faint = Color.white.opacity(0.32)
    static let stroke = Color.white.opacity(0.07)

    static let gradient = LinearGradient(colors: [redBright, red, redDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let glow = RadialGradient(colors: [red.opacity(0.35), .clear], center: .top, startRadius: 0, endRadius: 420)
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
        .foregroundStyle(strong ? .white : Theme.redBright)
        .background(Capsule().fill(strong ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Theme.red.opacity(0.14))))
    }
}

struct KindIcon: View {
    let kind: DeviceKind
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(kind == .unknown ? AnyShapeStyle(Theme.red.opacity(0.15)) : AnyShapeStyle(Theme.gradient))
            Image(systemName: kind.symbol)
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(kind == .unknown ? Theme.redBright : .white)
        }
        .frame(width: size, height: size)
        .shadow(color: kind == .unknown ? .clear : Theme.red.opacity(0.45), radius: size * 0.2, y: size * 0.06)
    }
}

struct RedButtonStyle: ButtonStyle {
    var prominent = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 14).padding(.vertical, 9)
            .frame(maxWidth: prominent ? .infinity : nil)
            .foregroundStyle(prominent ? .white : Theme.redBright)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(prominent ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Theme.red.opacity(0.13)))
            )
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(prominent ? 0.18 : 0.05)))
            .shadow(color: prominent ? Theme.red.opacity(0.5) : .clear, radius: 10, y: 3)
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
                    Circle().fill(.white).frame(width: 5, height: 5).shadow(color: Theme.red, radius: 4)
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
