//
//  IconLibrary.swift
//  Bovanta:Sport
//
//  Created on 2025-10-14
//

import SwiftUI
import Combine
import UIKit

/// Central registry of icons used across the app:
/// - Sports & Esports symbols
/// - Team badges (system or asset-based)
/// - Safe fallbacks (never returns a broken image)
///
/// Conventions for custom assets (if you add your own PNG/PDF to Assets):
///   - Sports:  "icon.sport.<key>"   e.g., "icon.sport.football"
///   - Team:    "icon.team.<slug>"   e.g., "icon.team.wolves"
///
/// Notes:
/// - Prefers custom asset if present; falls back to SF Symbol.
/// - All APIs are pure and side-effect free (no global state).
enum IconLibrary {

    // MARK: - Public: Sports (keys + resolution)

    /// Canonical sport keys (use them across the app to avoid typos).
    /// Matches your planned `SportKind` cases.
    static let sportKeys: [String] = [
        "football",
        "basketball",
        "volleyball",
        "tennis",
        "tabletennis",
        "hockey",
        "badminton",
        "esports.cs",
        "esports.dota",
        "esports.lol"
    ]

    /// Optional human-readable labels for pickers (UI only).
    static let sportLabels: [String: String] = [
        "football"     : "Football",
        "basketball"   : "Basketball",
        "volleyball"   : "Volleyball",
        "tennis"       : "Tennis",
        "tabletennis"  : "Table Tennis",
        "hockey"       : "Hockey",
        "badminton"    : "Badminton",
        "esports.cs"   : "CS",
        "esports.dota" : "Dota",
        "esports.lol"  : "LoL"
    ]

    /// Returns an Image for given sport key.
    /// Priority: custom asset "icon.sport.<key>" → SF Symbol → default.
    static func sportIcon(for key: String) -> Image {
        // 1) Custom asset
        let assetName = "icon.sport.\(key)"
        if hasAsset(named: assetName) {
            return Image(assetName)
        }

        // 2) SF Symbol
        if let sfName = sfSymbolForSport(key),
           hasSFSymbol(named: sfName) {
            return Image(systemName: sfName)
        }

        // 3) Default fallback (generic sports court)
        return Image(systemName: "sportscourt.fill")
    }

    /// Returns SF Symbol name (if we map one) for a sport key.
    /// Uses iOS 16+ sports glyphs where available.
    static func sfSymbolForSport(_ key: String) -> String? {
        switch key {
        case "football":     return "soccerball"
        case "basketball":   return "basketball"
        case "volleyball":   return "volleyball"
        case "tennis":       return "tennis.racket"
        case "tabletennis":  return "table.tennis"
        case "hockey":       return "hockey.puck"     // SF Symbols 5+
        case "badminton":    return "figure.badminton"
        case "esports.cs":   return "gamecontroller.fill"
        case "esports.dota": return "gamecontroller.fill"
        case "esports.lol":  return "gamecontroller.fill"
        default:             return nil
        }
    }

    // MARK: - Public: Team badges

    /// Returns an Image for team badge by preferred name.
    /// - If `name` starts with "sf:" → treat the rest as SF Symbol (e.g., "sf:shield.fill").
    /// - Else try custom asset "icon.team.<name>" (e.g., "icon.team.wolves").
    /// - Else if `name` itself is an existing asset → use it.
    /// - Else fallback to a neutral circle.
    static func teamBadge(named name: String) -> Image {
        // Explicit SF symbol channel: "sf:shield.fill"
        if name.hasPrefix("sf:") {
            let sf = String(name.dropFirst(3))
            if hasSFSymbol(named: sf) { return Image(systemName: sf) }
        }

        // Asset convention: icon.team.<slug>
        let slugAsset = "icon.team.\(name)"
        if hasAsset(named: slugAsset) {
            return Image(slugAsset)
        }

        // Raw asset name (in case user passes a direct asset key)
        if hasAsset(named: name) {
            return Image(name)
        }

        // Fallback: neutral badge
        return Image(systemName: "circle.fill")
    }

    /// Recommended SF Symbol badge names for teams (useful for pickers).
    static let recommendedTeamSF: [String] = [
        "shield.fill",
        "flag.filled.and.flag.crossed",
        "hexagon.fill",
        "seal.fill",
        "star.circle.fill",
        "flame.circle.fill",
        "bolt.circle.fill",
        "trophy.fill",
        "crown.fill",
        "face.smiling.inverse" // playful option
    ]

    // MARK: - Public: Generic UI glyphs

    static func add() -> Image { Image(systemName: "plus.circle.fill") }
    static func edit() -> Image { Image(systemName: "pencil") }
    static func delete() -> Image { Image(systemName: "trash.fill") }
    static func back() -> Image { Image(systemName: "chevron.left") }
    static func timer() -> Image { Image(systemName: "timer") }
    static func scoreUp() -> Image { Image(systemName: "plus") }
    static func scoreDown() -> Image { Image(systemName: "minus") }
    static func undo() -> Image { Image(systemName: "arrow.uturn.backward") }
    static func redo() -> Image { Image(systemName: "arrow.uturn.forward") }
    static func stats() -> Image { Image(systemName: "chart.bar.fill") }
    static func settings() -> Image { Image(systemName: "gearshape.fill") }
    static func team() -> Image { Image(systemName: "person.2.fill") }
    static func sport() -> Image { Image(systemName: "sportscourt.fill") }

    // MARK: - Public: Discovery helpers (for pickers)

    /// Returns a lightweight list for sport picker: (key, label, preview Image).
    static func sportPickerItems() -> [(key: String, label: String, icon: Image)] {
        sportKeys.map { key in
            let label = sportLabels[key] ?? key.capitalized
            return (key, label, sportIcon(for: key))
        }
    }

    /// Returns a set of recommended team badge images (system-only).
    static func teamBadgePickerItems() -> [(name: String, icon: Image)] {
        recommendedTeamSF.map { sf in ("sf:\(sf)", Image(systemName: sf)) }
    }

    // MARK: - Private: Capability checks

    /// Checks if an image asset exists in the main bundle's asset catalog.
    private static func hasAsset(named name: String) -> Bool {
        #if canImport(UIKit)
        return UIImage(named: name) != nil
        #else
        return Image(name) != nil // SwiftUI fallback (non-iOS)
        #endif
    }

    /// Checks if an SF Symbol with this name is available on current OS.
    private static func hasSFSymbol(named name: String) -> Bool {
        #if canImport(UIKit)
        return UIImage(systemName: name) != nil
        #else
        return true
        #endif
    }
}
