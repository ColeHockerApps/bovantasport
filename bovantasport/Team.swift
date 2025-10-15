//
//  Team.swift
//  Bovanta:Sport
//
//  Created on 2025-10-14
//

import SwiftUI
import Combine

/// Team model: belongs to a specific sport, has color/icon badge and a roster.
/// Value type with safe defaults and practical UI helpers.
public struct Team: Identifiable, Codable, Hashable, Sendable {
    // MARK: - Core
    public let id: UUID
    public var name: String
    public var sport: SportKind
    /// Index into ColorSwatches.teamSwatches (wrapped if out of range).
    public var colorIndex: Int
    /// Badge identifier:
    ///  - "sf:<symbol.name>" to force SF Symbol (e.g., "sf:shield.fill")
    ///  - "icon.team.<slug>" for asset-catalog images
    ///  - or any direct asset name (fallback will try it)
    public var badgeName: String
    public var players: [Player]

    // MARK: - Timestamps
    public var createdAt: Date
    public var updatedAt: Date

    // MARK: - Init

    public init(id: UUID = .init(),
                name: String,
                sport: SportKind,
                colorIndex: Int? = nil,
                badgeName: String = "sf:shield.fill",
                players: [Player] = [],
                createdAt: Date = .init(),
                updatedAt: Date = .init()) {
        self.id = id
        self.name = Team.sanitized(name)
        self.sport = sport
        // Prefer provided index; else derive deterministically from UUID.
        let rawIndex = colorIndex ?? ColorSwatches.teamColorIndex(for: id)
        self.colorIndex = Team.normalizeColorIndex(rawIndex)
        self.badgeName = Team.sanitizedBadge(badgeName)
        self.players = players
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - Derived

    public var displayName: String {
        name
    }

    public var playerCount: Int {
        players.count
    }

    /// Initials from team name (e.g., "Red Dragons" → "RD").
    public var initials: String {
        Team.initials(from: name)
    }

    /// Safe, wrapped color index within the palette bounds.
    public var normalizedColorIndex: Int {
        Team.normalizeColorIndex(colorIndex)
    }

    /// Resolved team color from ColorSwatches.
    public var color: Color {
        let idx = normalizedColorIndex
        return ColorSwatches.teamSwatches[safe: idx] ?? ColorSwatches.brandPrimary
    }

    /// Legible foreground for labels placed on team color.
    public var foregroundOnColor: Color {
        ColorSwatches.foregroundForTeam(index: normalizedColorIndex)
    }

    /// Resolved badge image using the shared IconLibrary policy.
    public var badge: Image {
        IconLibrary.teamBadge(named: badgeName)
    }

    /// True if team has a non-empty, trimmed name.
    public var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Membership

    public func hasPlayer(_ playerID: UUID) -> Bool {
        players.contains { $0.id == playerID }
    }

    public func hasPlayer(named query: String) -> Bool {
        let q = query.lowercased()
        return players.contains { $0.displayName.lowercased().contains(q) }
    }

    // MARK: - Matching / Search

    /// Case-insensitive search across team name, sport label/short label, and player names.
    public func matches(_ query: String) -> Bool {
        let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        if name.lowercased().contains(q) { return true }
        if sport.label.lowercased().contains(q) { return true }
        if sport.shortLabel.lowercased().contains(q) { return true }
        return players.contains { $0.matches(q) }
    }

    // MARK: - Withers (non-mutating updates)

    public func withName(_ newName: String) -> Team {
        var t = self
        t.name = Team.sanitized(newName)
        t.updatedAt = .init()
        return t
    }

    public func withSport(_ newSport: SportKind) -> Team {
        var t = self
        t.sport = newSport
        t.updatedAt = .init()
        return t
    }

    public func withColorIndex(_ newIndex: Int) -> Team {
        var t = self
        t.colorIndex = Team.normalizeColorIndex(newIndex)
        t.updatedAt = .init()
        return t
    }

    public func withBadgeName(_ newBadge: String) -> Team {
        var t = self
        t.badgeName = Team.sanitizedBadge(newBadge)
        t.updatedAt = .init()
        return t
    }

    public func withPlayers(_ newPlayers: [Player]) -> Team {
        var t = self
        t.players = newPlayers
        t.updatedAt = .init()
        return t
    }

    public func addingPlayer(_ player: Player) -> Team {
        guard !hasPlayer(player.id) else { return self }
        var t = self
        t.players = players + [player]
        t.updatedAt = .init()
        return t
    }

    public func updatingPlayer(_ player: Player) -> Team {
        var t = self
        if let idx = t.players.firstIndex(where: { $0.id == player.id }) {
            t.players[idx] = player
        } else {
            t.players.append(player)
        }
        t.updatedAt = .init()
        return t
    }

    public func removingPlayer(_ playerID: UUID) -> Team {
        var t = self
        t.players.removeAll { $0.id == playerID }
        t.updatedAt = .init()
        return t
    }

    // MARK: - Utilities

    /// Normalize/Wrap color index into palette bounds.
    private static func normalizeColorIndex(_ idx: Int) -> Int {
        let count = max(1, ColorSwatches.teamSwatches.count)
        let mod = idx % count
        return mod >= 0 ? mod : (mod + count)
    }

    /// Slug for persistence / URLs (not used externally but handy).
    public var slug: String {
        name
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }

    // MARK: - Sanitization

    public static func sanitized(_ raw: String) -> String {
        let trimmed = raw
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let collapsed = trimmed
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return collapsed
    }

    public static func sanitizedBadge(_ raw: String) -> String {
        let s = sanitized(raw)
        return s.isEmpty ? "sf:shield.fill" : s
    }

    public static func initials(from text: String) -> String {
        let parts = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }

        var letters: [String] = []
        if let first = parts.first { letters.append(String(first.prefix(1))) }
        if parts.count > 1, let last = parts.last { letters.append(String(last.prefix(1))) }

        let result = letters.joined().uppercased()
        if result.isEmpty, let c = text.unicodeScalars.first {
            return String(Character(c)).uppercased()
        }
        return result
    }
}

// MARK: - Array helpers

public extension Array where Element == Team {
    /// Sort teams by name (localized) then by sport.
    func sortedByName() -> [Team] {
        self.sorted {
            let lhs = $0.name.localizedCaseInsensitiveCompare($1.name)
            if lhs != .orderedSame { return lhs == .orderedAscending }
            return $0.sport.label.localizedCaseInsensitiveCompare($1.sport.label) == .orderedAscending
        }
    }

    /// Find a team by id.
    func first(id: UUID) -> Team? {
        first { $0.id == id }
    }

    /// Filter by sport.
    func filtered(sport: SportKind) -> [Team] {
        filter { $0.sport == sport }
    }
}

// MARK: - Safe index access

private extension Array {
    subscript (safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
