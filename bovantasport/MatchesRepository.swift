//
//  MatchesRepository.swift
//  Bovanta:Sport
//
//  Created on 2025-10-14
//

import SwiftUI
import Combine

/// Repository that manages the lifecycle and persistence of `Match` entities.
/// - Versioned Codable storage via `StorageService`
/// - Full runtime controls: score, set score, timer tick, end period, notes, resets
/// - Query helpers: by sport/team, finished/in-progress, search
public final class MatchesRepository: ObservableObject {
    // MARK: - Public state

    /// Chronological history (newest first).
    @Published public private(set) var history: [Match] = []

    // MARK: - Internals

    private let storage = StorageService.shared
    private var cancellables = Set<AnyCancellable>()

    /// Increment when the stored schema for matches changes.
    private let storageVersion: Int = 1
    private let storageKey: StorageService.Key = .matches

    // MARK: - Init

    public init() {
        // Load persisted matches
        let loaded = storage.load([Match].self,
                                  for: storageKey,
                                  default: [],
                                  targetVersion: storageVersion,
                                  allowMigrations: true)
        self.history = loaded.dedupByID().sortedByDateDesc()

        // Observe external storage changes (e.g., global reset)
        storage.didChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] key in
                guard let self, key == self.storageKey else { return }
                let fresh = self.storage.load([Match].self,
                                              for: self.storageKey,
                                              default: [],
                                              targetVersion: self.storageVersion,
                                              allowMigrations: true)
                self.history = fresh.dedupByID().sortedByDateDesc()
            }
            .store(in: &cancellables)
    }

    // MARK: - Persistence

    private func persist() {
        storage.save(history, for: storageKey, version: storageVersion)
    }

    // MARK: - Creation

    /// Create and add a new match with validated rules.
    @discardableResult
    public func createMatch(sport: SportKind,
                            teamA: Team,
                            teamB: Team,
                            rules: MatchRules) -> Match {
        let m = Match(sport: sport, teamA: teamA, teamB: teamB, rules: rules)
        history.insert(m, at: 0)
        persist()
        return m
    }

    /// Insert an existing match (keeps its id and timestamps).
    @discardableResult
    public func add(_ match: Match) -> Match {
        history.insert(match, at: 0)
        history = history.dedupByID().sortedByDateDesc()
        persist()
        return match
    }

    // MARK: - Updates (mutating runtime state)

    /// Increment/decrement score for a side.
    @discardableResult
    public func score(matchID: UUID, side: Match.Side, delta: Int = 1) -> Match? {
        guard var m = match(by: matchID) else { return nil }
        m.score(side, delta: delta)
        return replace(m)
    }

    /// Set absolute score for current context (points, current set, or timed).
    @discardableResult
    public func setScore(matchID: UUID, pointsA: Int, pointsB: Int) -> Match? {
        guard var m = match(by: matchID) else { return nil }
        m.setScore(pointsA: pointsA, pointsB: pointsB)
        return replace(m)
    }

    /// Advance match timer by `seconds` (timed rules).
    @discardableResult
    public func tick(matchID: UUID, seconds: Int = 1) -> Match? {
        guard var m = match(by: matchID) else { return nil }
        m.tick(seconds: seconds)
        return replace(m)
    }

    /// Force end of the current period (timed rules).
    @discardableResult
    public func endPeriod(matchID: UUID) -> Match? {
        guard var m = match(by: matchID) else { return nil }
        m.endPeriod()
        return replace(m)
    }

    /// Add a free-form note to the event log.
    @discardableResult
    public func addNote(matchID: UUID, text: String) -> Match? {
        guard var m = match(by: matchID) else { return nil }
        m.addNote(text)
        return replace(m)
    }

    /// Reset only the current set (sets mode).
    @discardableResult
    public func resetCurrentSet(matchID: UUID) -> Match? {
        guard var m = match(by: matchID) else { return nil }
        m.resetCurrentSet()
        return replace(m)
    }

    /// Reset entire match state (keeps teams/rules).
    @discardableResult
    public func resetAll(matchID: UUID) -> Match? {
        guard var m = match(by: matchID) else { return nil }
        m.resetAll()
        return replace(m)
    }

    /// Undo the last state change (if available).
    @discardableResult
    public func undo(matchID: UUID) -> Match? {
        guard var m = match(by: matchID) else { return nil }
        m.undo()
        return replace(m)
    }

    /// Redo an undone change (if available).
    @discardableResult
    public func redo(matchID: UUID) -> Match? {
        guard var m = match(by: matchID) else { return nil }
        m.redo()
        return replace(m)
    }

    /// Create and insert a rematch with optional side swap.
    @discardableResult
    public func rematch(from matchID: UUID, swapped: Bool = false) -> Match? {
        guard let m = match(by: matchID) else { return nil }
        let r = m.rematch(swapped: swapped)
        history.insert(r, at: 0)
        persist()
        return r
    }

    // MARK: - Direct replacement / update

    /// Replace a match in history by id and persist.
    @discardableResult
    public func update(_ match: Match) -> Match {
        replace(match)
    }

    @discardableResult
    private func replace(_ match: Match) -> Match {
        if let i = history.firstIndex(where: { $0.id == match.id }) {
            history[i] = match
        } else {
            history.insert(match, at: 0)
        }
        history = history.sortedByDateDesc()
        persist()
        return match
    }

    // MARK: - Deletion

    public func delete(matchID: UUID) {
        history.removeAll { $0.id == matchID }
        persist()
    }

    public func removeAll() {
        history.removeAll()
        persist()
    }

    public func replaceAll(with matches: [Match]) {
        history = matches.dedupByID().sortedByDateDesc()
        persist()
    }

    // MARK: - Queries

    public func match(by id: UUID) -> Match? {
        history.first { $0.id == id }
    }

    /// Recent N matches (newest first).
    public func recent(limit: Int = 10) -> [Match] {
        Array(history.prefix(max(0, limit)))
    }

    /// All matches for a given sport.
    public func matches(for sport: SportKind) -> [Match] {
        history.filter { $0.sport == sport }.sortedByDateDesc()
    }

    /// All matches where the given team participated.
    public func matches(forTeam teamID: UUID) -> [Match] {
        history.filter { $0.teamA.id == teamID || $0.teamB.id == teamID }.sortedByDateDesc()
    }

    /// Finished or in-progress filters.
    public func finished(_ isFinished: Bool = true) -> [Match] {
        history.filter { $0.isFinished == isFinished }.sortedByDateDesc()
    }

    /// Simple search over team names and sport labels.
    public func search(_ query: String) -> [Match] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return history }
        return history.filter { m in
            m.teamA.name.lowercased().contains(q) ||
            m.teamB.name.lowercased().contains(q) ||
            m.sport.label.lowercased().contains(q) ||
            m.sport.shortLabel.lowercased().contains(q)
        }.sortedByDateDesc()
    }

    /// Last head-to-head between two teams (any sport).
    public func lastHeadToHead(_ a: UUID, _ b: UUID) -> Match? {
        history.first {
            ($0.teamA.id == a && $0.teamB.id == b) || ($0.teamA.id == b && $0.teamB.id == a)
        }
    }
}

// MARK: - Array utilities

private extension Array where Element == Match {
    func dedupByID() -> [Match] {
        var seen = Set<UUID>()
        var out: [Match] = []
        out.reserveCapacity(count)
        for m in self {
            if !seen.contains(m.id) {
                seen.insert(m.id)
                out.append(m)
            }
        }
        return out
    }

    func sortedByDateDesc() -> [Match] {
        sorted { lhs, rhs in
            // Prefer updatedAt if different; else createdAt
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.createdAt > rhs.createdAt
        }
    }
}
