//
//  ColorSwatches.swift
//  Bovanta:Sport
//
//  Created on 2025-10-14
//

import SwiftUI
import Combine
#if canImport(UIKit)
import UIKit
#endif
/// Centralized color system:
/// - Brand & neutrals
/// - Status indicators (success/warning/danger/info)
/// - Team swatches (indexed palette + hashing helpers)
/// - Sport-accent mapping (works with IconLibrary.sportKeys)
/// - Utilities: contrast, legible foreground, gradients, hashing
///
/// Pure SwiftUI colors; no placeholders.
enum ColorSwatches {

    // MARK: - Brand & Neutrals

    static let brandPrimary   = Color(red: 30/255,  green: 136/255, blue: 229/255) // #1E88E5
    static let brandSecondary = Color(red: 25/255,  green: 118/255, blue: 210/255) // #1976D2
    static let brandTertiary  = Color(red: 21/255,  green: 101/255, blue: 192/255) // #1565C0

    static let bgDark         = Color(red: 10/255,  green: 14/255,  blue: 20/255)  // app background (dark)
    static let surfaceDark    = Color(red: 18/255,  green: 24/255,  blue: 32/255)  // cards
    static let secondaryDark  = Color(red: 24/255,  green: 32/255,  blue: 44/255)  // toolbars

    static let textPrimaryDark   = Color.white
    static let textSecondaryDark = Color.white.opacity(0.7)

    static let bgLight        = Color(red: 242/255, green: 245/255, blue: 250/255)
    static let surfaceLight   = Color.white
    static let secondaryLight = Color(red: 230/255, green: 235/255, blue: 240/255)

    static let textPrimaryLight   = Color(red: 33/255,  green: 33/255,  blue: 33/255)
    static let textSecondaryLight = Color(red: 100/255, green: 100/255, blue: 100/255)

    // MARK: - Status / Indicators

    static let success = Color.green.opacity(0.90)
    static let warning = Color.orange.opacity(0.95)
    static let danger  = Color.red.opacity(0.92)
    static let info    = Color.cyan.opacity(0.92)

    // MARK: - Team Swatches (indexed palette)
    // Bright, high-contrast hues for badges/kits.
    static let teamSwatches: [Color] = [
        Color(hue: 0.58, saturation: 0.72, brightness: 0.95), // blue
        Color(hue: 0.03, saturation: 0.80, brightness: 0.96), // red
        Color(hue: 0.12, saturation: 0.85, brightness: 0.95), // yellow
        Color(hue: 0.37, saturation: 0.70, brightness: 0.92), // green
        Color(hue: 0.80, saturation: 0.58, brightness: 0.94), // purple
        Color(hue: 0.92, saturation: 0.60, brightness: 0.95), // pink
        Color(hue: 0.50, saturation: 0.55, brightness: 0.90), // teal
        Color(hue: 0.08, saturation: 0.75, brightness: 0.90), // orange
        Color(hue: 0.67, saturation: 0.55, brightness: 0.88), // indigo
        Color(hue: 0.98, saturation: 0.45, brightness: 0.88)  // magenta
    ]

    /// Deterministic color index for a given UUID (stable per team).
    static func teamColorIndex(for id: UUID) -> Int {
        let hash = hash64(of: id.uuidString)
        return Int(hash % UInt64(teamSwatches.count))
    }

    /// Next available color index not in `used`, cycling through palette.
    static func nextTeamColorIndex(start: Int = 0, used: Set<Int>) -> Int {
        let n = teamSwatches.count
        guard n > 0 else { return 0 }
        for i in 0..<n {
            let idx = (start + i) % n
            if !used.contains(idx) { return idx }
        }
        // if all used — just cycle
        return start % n
    }

    /// Suggest a readable foreground for a team swatch (white/black).
    static func foregroundForTeam(index: Int) -> Color {
        let bg = teamSwatches[safe: index] ?? brandPrimary
        return legibleForeground(on: bg)
    }

    // MARK: - Sport Accent Mapping (keyed to IconLibrary.sportKeys)

    static func sportAccent(for key: String) -> Color {
        switch key {
        case "football":     return Color(hue: 0.36, saturation: 0.65, brightness: 0.92) // turf green
        case "basketball":   return Color(hue: 0.06, saturation: 0.80, brightness: 0.95) // orange court
        case "volleyball":   return Color(hue: 0.58, saturation: 0.30, brightness: 0.95) // light blue
        case "tennis":       return Color(hue: 0.18, saturation: 0.80, brightness: 0.95) // neon yellow-green
        case "tabletennis":  return Color(hue: 0.56, saturation: 0.55, brightness: 0.90) // cyan/teal
        case "hockey":       return Color(hue: 0.62, saturation: 0.35, brightness: 0.92) // ice blue
        case "badminton":    return Color(hue: 0.78, saturation: 0.45, brightness: 0.92) // violet
        case "esports.cs":   return Color(hue: 0.00, saturation: 0.00, brightness: 0.80) // neutral steel
        case "esports.dota": return Color(hue: 0.02, saturation: 0.80, brightness: 0.90) // dota red
        case "esports.lol":  return Color(hue: 0.55, saturation: 0.70, brightness: 0.88) // arcane blue
        default:             return brandPrimary
        }
    }

    // MARK: - Utilities

    /// Legible foreground (black/white) based on perceived luminance of `background`.
    static func legibleForeground(on background: Color) -> Color {
        let rgb = background.rgb
        // Luminance (sRGB) — WCAG-style formula
        let luma = 0.2126 * rgb.r + 0.7152 * rgb.g + 0.0722 * rgb.b
        return luma > 0.6 ? Color.black : Color.white
    }

    /// Soft vertical gradient with a slightly darker top shade.
    static func softVerticalGradient(_ base: Color) -> LinearGradient {
        let rgb = base.rgb
        let darker = Color(
            red: max(0, rgb.r - 0.08),
            green: max(0, rgb.g - 0.08),
            blue: max(0, rgb.b - 0.08)
        )
        return LinearGradient(
            colors: [darker.opacity(0.95), base.opacity(0.95)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Ring gradient for circular badges.
    static func ringGradient(_ base: Color) -> AngularGradient {
        let rgb = base.rgb
        let light = Color(
            red: min(1, rgb.r + 0.10),
            green: min(1, rgb.g + 0.10),
            blue: min(1, rgb.b + 0.10)
        )
        return AngularGradient(
            gradient: Gradient(colors: [light, base, light]),
            center: .center
        )
    }

    /// Subtle shadow color matched to a given base hue.
    static func shadow(for base: Color) -> Color {
        base.opacity(0.35)
    }

    /// Contrast ratio (approximate) for background/foreground readability checks.
    static func contrastRatio(bg: Color, fg: Color) -> CGFloat {
        let L1 = bg.relativeLuminance
        let L2 = fg.relativeLuminance
        let (bright, dark) = (max(L1, L2), min(L1, L2))
        return (bright + 0.05) / (dark + 0.05)
    }

    /// Ensures minimum contrast by returning either `primary` or `secondary` text color.
    static func bestTextColor(on background: Color,
                              primary: Color = .white,
                              secondary: Color = .black,
                              minRatio: CGFloat = 4.5) -> Color {
        let p = contrastRatio(bg: background, fg: primary)
        let s = contrastRatio(bg: background, fg: secondary)
        if p >= minRatio && p >= s { return primary }
        if s >= minRatio && s > p { return secondary }
        // Fallback to more legible of the two
        return p >= s ? primary : secondary
    }

    // MARK: - Internal helpers

    /// 64-bit FNV-1a hash for stable color indexing.
    private static func hash64(of string: String) -> UInt64 {
        let fnvOffset: UInt64 = 0xcbf29ce484222325
        let fnvPrime: UInt64  = 0x00000100000001B3
        var hash = fnvOffset
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* fnvPrime
        }
        return hash
    }
}

// MARK: - Extensions

private extension Array {
    subscript (safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
private extension Color {
    /// Extract linearized sRGB components for computations.
    var rgb: (r: CGFloat, g: CGFloat, b: CGFloat) {
        #if canImport(UIKit)
        let ui: UIColor
        if #available(iOS 14.0, *) {
            ui = UIColor(self)            // Safe on iOS 14+
        } else {
            ui = .white                   // Fallback (older targets)
        }

        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if ui.getRed(&r, green: &g, blue: &b, alpha: &a) {
            func lin(_ c: CGFloat) -> CGFloat {
                c <= 0.04045 ? (c / 12.92) : pow((c + 0.055) / 1.055, 2.4)
            }
            return (lin(r), lin(g), lin(b))
        } else {
            // Non-RGB colors fallback
            return (0.5, 0.5, 0.5)
        }
        #else
        // Best-effort for non-UIKit platforms
        return (0.5, 0.5, 0.5)
        #endif
    }

    /// Relative luminance (0…1) per WCAG using linearized sRGB.
    var relativeLuminance: CGFloat {
        let c = rgb
        return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
    }
}
