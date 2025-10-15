//
//  Player.swift
//  Bovanta:Sport
//
//  Created on 2025-10-14
//

import SwiftUI
import Combine

/// A single participant that can belong to one or more teams.
/// Immutable value semantics with small, practical helpers for UI.
public struct Player: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var nickname: String?
    public var createdAt: Date
    public var updatedAt: Date

    // MARK: - Init

    public init(id: UUID = .init(),
                name: String,
                nickname: String? = nil,
                createdAt: Date = .init(),
                updatedAt: Date = .init()) {
        self.id = id
        self.name = Player.sanitized(name)
        self.nickname = Player.sanitizedEmptyNil(nickname)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - Derived

    /// Preferred display string (nickname → name).
    public var displayName: String {
        (nickname?.isEmpty == false ? nickname! : name)
    }

    /// Uppercased initials for avatar chips (e.g., "AB").
    public var initials: String {
        Player.initials(from: displayName)
    }

    /// True if the name is non-empty after trimming.
    public var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Deterministic color index for avatar/label usage (maps to ColorSwatches.teamSwatches or similar).
    public var colorIndex: Int {
        Player.colorIndex(for: id)
    }

    // MARK: - Withers (non-mutating updates)

    public func withName(_ newName: String) -> Player {
        var copy = self
        copy.name = Player.sanitized(newName)
        copy.updatedAt = .init()
        return copy
    }

    public func withNickname(_ newNickname: String?) -> Player {
        var copy = self
        copy.nickname = Player.sanitizedEmptyNil(newNickname)
        copy.updatedAt = .init()
        return copy
    }

    // MARK: - Static helpers

    /// Trim and collapse spaces; remove newlines.
    public static func sanitized(_ raw: String) -> String {
        let trimmed = raw
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Collapse consecutive spaces
        let collapsed = trimmed
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return collapsed
    }

    /// Apply `sanitized(_:)` and convert empty result to `nil`.
    public static func sanitizedEmptyNil(_ raw: String?) -> String? {
        guard let raw = raw else { return nil }
        let s = sanitized(raw)
        return s.isEmpty ? nil : s
    }

    /// Build initials from a name or nickname.
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

    /// Stable color index by UUID (FNV-1a 64-bit).
    public static func colorIndex(for id: UUID, paletteCount: Int = 10) -> Int {
        let h = fnv1a64(id.uuidString)
        let count = max(1, paletteCount)
        return Int(h % UInt64(count))
    }

    /// Case-insensitive search match against name/nickname.
    public func matches(_ query: String) -> Bool {
        let q = query.lowercased()
        if name.lowercased().contains(q) { return true }
        if (nickname ?? "").lowercased().contains(q) { return true }
        return false
    }

    // MARK: - Private hashing

    private static func fnv1a64(_ string: String) -> UInt64 {
        let offset: UInt64 = 0xcbf29ce484222325
        let prime:  UInt64 = 0x00000100000001B3
        var hash = offset
        for b in string.utf8 {
            hash ^= UInt64(b)
            hash = hash &* prime
        }
        return hash
    }
}

// MARK: - Sorting helpers

public extension Array where Element == Player {
    /// Sort players by display name (localized, case-insensitive).
    func sortedByDisplayName() -> [Player] {
        self.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }
}
