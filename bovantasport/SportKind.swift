//
//  SportKind.swift
//  Bovanta:Sport
//
//  Created on 2025-10-14
//

import SwiftUI
import Combine

/// Supported sports (including esports) with UI helpers.
/// Pure enum with stable keys for storage and icon/color resolution.
public enum SportKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case football
    case basketball
    case volleyball
    case tennis
    case tableTennis
    case hockey
    case badminton
    case esportsCS
    case esportsDota
    case esportsLOL

    // MARK: - Identifiable

    public var id: String { rawValue }

    // MARK: - Stable keys (match IconLibrary & ColorSwatches maps)

    /// Canonical string key used for assets and color accents.
    public var key: String {
        switch self {
        case .football:     return "football"
        case .basketball:   return "basketball"
        case .volleyball:   return "volleyball"
        case .tennis:       return "tennis"
        case .tableTennis:  return "tabletennis"
        case .hockey:       return "hockey"
        case .badminton:    return "badminton"
        case .esportsCS:    return "esports.cs"
        case .esportsDota:  return "esports.dota"
        case .esportsLOL:   return "esports.lol"
        }
    }

    /// Construct from a canonical key; falls back to football if unknown.
    public static func fromKey(_ key: String) -> SportKind {
        switch key.lowercased() {
        case "football":      return .football
        case "basketball":    return .basketball
        case "volleyball":    return .volleyball
        case "tennis":        return .tennis
        case "tabletennis":   return .tableTennis
        case "hockey":        return .hockey
        case "badminton":     return .badminton
        case "esports.cs":    return .esportsCS
        case "esports.dota":  return .esportsDota
        case "esports.lol":   return .esportsLOL
        default:              return .football
        }
    }

    // MARK: - Labels

    /// Full label for UI titles and pickers.
    public var label: String {
        switch self {
        case .football:     return "Football"
        case .basketball:   return "Basketball"
        case .volleyball:   return "Volleyball"
        case .tennis:       return "Tennis"
        case .tableTennis:  return "Table Tennis"
        case .hockey:       return "Hockey"
        case .badminton:    return "Badminton"
        case .esportsCS:    return "CS"
        case .esportsDota:  return "Dota"
        case .esportsLOL:   return "LoL"
        }
    }

    /// Compact label for chips/badges.
    public var shortLabel: String {
        switch self {
        case .tableTennis:  return "TT"
        case .esportsCS:    return "CS"
        case .esportsDota:  return "Dota"
        case .esportsLOL:   return "LoL"
        default:            return label
        }
    }

    // MARK: - Icons & Accent

    /// SF Symbol name suitable for the sport (used as a fallback).
    public var sfSymbolName: String {
        switch self {
        case .football:     return "soccerball"
        case .basketball:   return "basketball"
        case .volleyball:   return "volleyball"
        case .tennis:       return "tennis.racket"
        case .tableTennis:  return "table.tennis"
        case .hockey:       return "hockey.puck"
        case .badminton:    return "figure.badminton"
        case .esportsCS,
             .esportsDota,
             .esportsLOL:  return "gamecontroller.fill"
        }
    }

    /// Resolved Image for the sport (custom asset → SF Symbol → generic).
    public var icon: Image {
        IconLibrary.sportIcon(for: key)
    }

    /// Accent color associated with the sport.
    public var accent: Color {
        ColorSwatches.sportAccent(for: key)
    }

    // MARK: - Gameplay traits (used by MatchRules/Scoreboard defaults)

    /// Sports that typically play in sets (true) vs continuous time/periods (false).
    public var supportsSets: Bool {
        switch self {
        case .tennis, .tableTennis, .volleyball, .badminton:
            return true
        default:
            return false
        }
    }

    /// Sports that commonly use a game clock/periods by default.
    public var usesTimerByDefault: Bool {
        switch self {
        case .football, .basketball, .hockey:
            return true
        default:
            return false
        }
    }

    // MARK: - Picker helpers

    /// Convenience data for sport pickers.
    public static func pickerItems() -> [(kind: SportKind, label: String, icon: Image, accent: Color)] {
        SportKind.allCases.map { kind in
            (kind, kind.label, kind.icon, kind.accent)
        }
    }
}
