//
//  TeamsRepository.swift
//  Bovanta:Sport
//
//  Created on 2025-10-14
//

import SwiftUI
import Combine

/// Repository for managing Teams (CRUD, search, persistence).
/// - Stores data via `StorageService` (versioned)
/// - Publishes changes with `@Published`
/// - Provides helpers for color/icon selection and player management
public final class TeamsRepository: ObservableObject {
    // MARK: - Public state

    @Published public private(set) var teams: [Team] = []

    // MARK: - Internals

    private let storage = StorageService.shared
    private var cancellables = Set<AnyCancellable>()

    /// Increment when you change the storage schema for teams payload.
    private let storageVersion: Int = 1
    private let storageKey: StorageService.Key = .teams

    // MARK: - Init

    public init() {
        // Load persisted teams (or empty)
        self.teams = storage.load([Team].self,
                                  for: storageKey,
                                  default: [],
                                  targetVersion: storageVersion,
                                  allowMigrations: true)
            .dedupByID()
            .sortedByName()

        // React to external storage clears (e.g., full reset from Settings)
        storage.didChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] key in
                guard let self = self, key == self.storageKey else { return }
                let fresh = self.storage.load([Team].self,
                                              for: self.storageKey,
                                              default: [],
                                              targetVersion: self.storageVersion,
                                              allowMigrations: true)
                self.teams = fresh.dedupByID().sortedByName()
            }
            .store(in: &cancellables)
    }

    // MARK: - Persistence

    private func persist() {
        storage.save(teams, for: storageKey, version: storageVersion)
    }

    // MARK: - CRUD

    /// Create and insert a new team. Color index auto-assigned if nil.
    @discardableResult
    public func createTeam(name: String,
                           sport: SportKind,
                           badgeName: String = "sf:shield.fill",
                           colorIndex: Int? = nil,
                           players: [Player] = []) -> Team {
        let idx = colorIndex ?? suggestColorIndex()
        let team = Team(name: name,
                        sport: sport,
                        colorIndex: idx,
                        badgeName: Team.sanitizedBadge(badgeName),
                        players: players)
        teams.append(team)
        teams = teams.dedupByID().sortedByName()
        persist()
        return team
    }

    /// Insert an existing team object (e.g., imported from elsewhere in the app).
    @discardableResult
    public func add(_ team: Team) -> Team {
        teams.append(team)
        teams = teams.dedupByID().sortedByName()
        persist()
        return team
    }

    /// Update (replace) a team by id.
    public func update(_ team: Team) {
        guard let idx = teams.firstIndex(where: { $0.id == team.id }) else { return }
        teams[idx] = team
        teams = teams.sortedByName()
        persist()
    }

    /// Rename a team by id.
    public func rename(teamID: UUID, to newName: String) {
        guard let idx = teams.firstIndex(where: { $0.id == teamID }) else { return }
        teams[idx] = teams[idx].withName(newName)
        teams = teams.sortedByName()
        persist()
    }

    /// Change a team's sport.
    public func setSport(teamID: UUID, to sport: SportKind) {
        guard let idx = teams.firstIndex(where: { $0.id == teamID }) else { return }
        teams[idx] = teams[idx].withSport(sport)
        teams = teams.sortedByName()
        persist()
    }

    /// Change a team's badge (icon).
    public func setBadge(teamID: UUID, to badgeName: String) {
        guard let idx = teams.firstIndex(where: { $0.id == teamID }) else { return }
        teams[idx] = teams[idx].withBadgeName(badgeName)
        persist()
    }

    /// Change a team's color (palette index).
    public func setColor(teamID: UUID, to colorIndex: Int) {
        guard let idx = teams.firstIndex(where: { $0.id == teamID }) else { return }
        teams[idx] = teams[idx].withColorIndex(colorIndex)
        persist()
    }

    /// Delete a team by id.
    public func delete(teamID: UUID) {
        teams.removeAll { $0.id == teamID }
        persist()
    }

    /// Duplicate a team (new id, same properties; optionally add "Copy" suffix).
    @discardableResult
    public func duplicate(teamID: UUID, nameSuffix: String = " Copy") -> Team? {
        guard let original = teams.first(where: { $0.id == teamID }) else { return nil }
        let dup = Team(name: original.name + nameSuffix,
                       sport: original.sport,
                       colorIndex: suggestColorIndex(),
                       badgeName: original.badgeName,
                       players: original.players)
        teams.append(dup)
        teams = teams.sortedByName()
        persist()
        return dup
    }

    // MARK: - Player management

    public func addPlayer(to teamID: UUID, player: Player) {
        guard let idx = teams.firstIndex(where: { $0.id == teamID }) else { return }
        teams[idx] = teams[idx].addingPlayer(player)
        persist()
    }

    public func updatePlayer(in teamID: UUID, player: Player) {
        guard let idx = teams.firstIndex(where: { $0.id == teamID }) else { return }
        teams[idx] = teams[idx].updatingPlayer(player)
        persist()
    }

    public func removePlayer(from teamID: UUID, playerID: UUID) {
        guard let idx = teams.firstIndex(where: { $0.id == teamID }) else { return }
        teams[idx] = teams[idx].removingPlayer(playerID)
        persist()
    }

    // MARK: - Queries

    public func team(by id: UUID) -> Team? {
        teams.first { $0.id == id }
    }

    public func teams(for sport: SportKind) -> [Team] {
        teams.filtered(sport: sport).sortedByName()
    }

    public func search(_ query: String) -> [Team] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return teams.sortedByName() }
        return teams.filter { $0.matches(q) }.sortedByName()
    }

    /// Returns a color index that is currently least used among teams, preferring free slots.
    public func suggestColorIndex() -> Int {
        let used = Set(teams.map { $0.normalizedColorIndex })
        return ColorSwatches.nextTeamColorIndex(start: 0, used: used)
    }

    /// Suggest a badge SF symbol that isn't overused (simple round-robin).
    public func suggestBadgeName() -> String {
        // Simple strategy: pick by count usage
        let counts = IconLibrary.recommendedTeamSF.reduce(into: [String: Int]()) { acc, name in
            acc[name] = 0
        }
        var mutable = counts
        for t in teams {
            if t.badgeName.hasPrefix("sf:") {
                let sf = String(t.badgeName.dropFirst(3))
                if mutable[sf] != nil { mutable[sf]! += 1 }
            }
        }
        // Pick the least-used symbol; fallback to first
        let candidate = mutable.min { $0.value < $1.value }?.key ?? IconLibrary.recommendedTeamSF.first!
        return "sf:\(candidate)"
    }

    // MARK: - Bulk ops

    /// Replace all teams (used carefully, e.g., after import or migration).
    public func replaceAll(with newTeams: [Team]) {
        teams = newTeams.dedupByID().sortedByName()
        persist()
    }

    /// Remove all teams.
    public func removeAll() {
        teams.removeAll()
        persist()
    }
}

// MARK: - Array utilities

private extension Array where Element == Team {
    func dedupByID() -> [Team] {
        var seen = Set<UUID>()
        var out: [Team] = []
        out.reserveCapacity(count)
        for t in self {
            if !seen.contains(t.id) {
                seen.insert(t.id)
                out.append(t)
            }
        }
        return out
    }
}
