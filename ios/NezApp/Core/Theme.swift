import SwiftUI
import UIKit

/// Palette « parfumerie nocturne », la même que la présentation PDF.
enum Theme {
    static let bg = Color(hex: "#100C18")
    static let ink = Color(hex: "#F4EFE8")
    static let muted = Color(hex: "#A79FB5")
    static let hair = Color.white.opacity(0.12)
    static let gold = Color(hex: "#E8C27A")
    static let rose = Color(hex: "#F27BA0")
    static let mint = Color(hex: "#6FE3C1")
    static let lilac = Color(hex: "#A98BFF")
    static let sky = Color(hex: "#6CB8FF")
    static let ember = Color(hex: "#FF8A5B")

    static func level(_ level: String) -> Color {
        switch level {
        case "danger": return Color(hex: "#F25C54")
        case "warning": return ember
        case "info": return sky
        default: return mint
        }
    }

    static func levelName(_ level: String) -> String {
        switch level {
        case "danger": return "Danger"
        case "warning": return "Attention"
        case "info": return "Info"
        default: return "Aucune"
        }
    }
}

extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        func c(_ x: CGFloat) -> Int { Int((min(max(x, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", c(r), c(g), c(b))
    }
}

extension Font {
    /// Titres en italique serif, comme la présentation.
    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .regular, design: .serif).italic() }
}

/// Fond sombre avec des « nuages d'odeur » lumineux.
struct GlowBackground: View {
    var colors: [Color] = [Theme.rose, Theme.lilac, Theme.mint]

    var body: some View {
        ZStack {
            Theme.bg
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                Circle().fill(colors[0 % colors.count].opacity(0.30)).frame(width: w * 1.1)
                    .position(x: w * 0.05, y: h * 0.12).blur(radius: 90)
                Circle().fill(colors[1 % colors.count].opacity(0.28)).frame(width: w * 1.2)
                    .position(x: w * 1.0, y: h * 0.55).blur(radius: 110)
                Circle().fill(colors[2 % colors.count].opacity(0.18)).frame(width: w * 0.9)
                    .position(x: w * 0.2, y: h * 1.0).blur(radius: 100)
            }
        }
        .ignoresSafeArea()
    }
}

/// Carte en verre dépoli.
struct Glass: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.hair, lineWidth: 0.8))
    }
}

extension View {
    func glass(padding: CGFloat = 16) -> some View { modifier(Glass(padding: padding)) }
}

/// Petit titre en capitales espacées (« kicker »).
struct Kicker: View {
    let text: String
    var color: Color = Theme.gold
    init(_ text: String, color: Color = Theme.gold) { self.text = text; self.color = color }
    var body: some View {
        Text(text.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(2.4).foregroundStyle(color)
    }
}

/// En-tête de page : kicker + titre serif italique + filet.
struct PageHeader: View {
    let kicker: String
    let title: String
    var color: Color = Theme.gold
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Kicker(kicker, color: color)
            Text(title).font(.display(36)).foregroundStyle(Theme.ink)
            Rectangle().fill(color).frame(width: 52, height: 1.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Pastille lumineuse.
struct GlowDot: View {
    var color: Color
    var size: CGFloat = 10
    var body: some View {
        Circle().fill(color).frame(width: size, height: size).shadow(color: color, radius: size * 0.8)
    }
}

/// Bouton principal doré.
struct PrimaryButtonStyle: ButtonStyle {
    var color: Color = Theme.gold
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Theme.bg)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Capsule().fill(color))
            .shadow(color: color.opacity(0.45), radius: configuration.isPressed ? 4 : 14)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

/// Bouton secondaire en contour.
struct GhostButtonStyle: ButtonStyle {
    var color: Color = Theme.ink
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(color)
            .padding(.vertical, 10).padding(.horizontal, 16)
            .background(Capsule().fill(color.opacity(configuration.isPressed ? 0.18 : 0.08)))
            .overlay(Capsule().stroke(color.opacity(0.5), lineWidth: 0.8))
    }
}
