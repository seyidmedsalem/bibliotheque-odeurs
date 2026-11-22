import SwiftUI
import UIKit

/// Style Apple natif : couleurs du système, mode clair et sombre automatiques.
enum Theme {
    static func level(_ level: String) -> Color {
        switch level {
        case "danger": return .red
        case "warning": return .orange
        case "info": return .blue
        default: return .green
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

    static func levelIcon(_ level: String) -> String {
        switch level {
        case "danger": return "exclamationmark.octagon.fill"
        case "warning": return "exclamationmark.triangle.fill"
        case "info": return "info.circle.fill"
        default: return "checkmark.circle.fill"
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
