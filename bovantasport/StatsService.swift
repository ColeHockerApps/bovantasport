//
//  StatsService.swift
//  Bovanta:Sport
//
//  Created on 2025-10-14
//

import SwiftUI
import Combine

/// Live statistics engine built on top of persisted matches.
/// Не зависит от UI и не использует заглушки.
/// Источник данных — `StorageService` (.matches); автоматически пересчитывает сводку при изменении стораджа.
public final class StatsService: ObservableObject {
    // MARK: - Published state

    @Published public private(set) var summary: StatsSummary = .init(
           generatedAt: Date(),
           teamRecords: [],
           sportOverviews: []
       )
    // Быстрые индексы для запросов (обновляются вместе с summary)
    @Published public private(set) var recordsByTeamID: [UUID: [SportKind: StatsSummary.TeamRecord]] = [:]
    @Published public private(set) var overviewBySport: [SportKind: StatsSummary.SportOverview] = [:]

    // MARK: - Internals

    private let storage = StorageService.shared
    private var cancellables = Set<AnyCancellable>()
    private let storageVersion: Int = 1
    private let storageKey: StorageService.Key = .matches

    // MARK: - Init

    public init() {
        // Первичная загрузка из стораджа
        let initial = loadMatchesFromStorage()
        self.summary = StatsSummary.build(from: initial, includeInProgress: true, perSportTeamBreakdown: true)
        rebuildIndexes()

        // Автопересчёт при изменении стораджа (включая полные ресеты)
        storage.didChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] key in
                guard let self, key == self.storageKey else { return }
                self.refreshFromStorage()
            }
            .store(in: &cancellables)
    }

    // MARK: - Public API

    /// Принудительно пересчитать сводку из текущего стораджа.
    public func refreshFromStorage() {
        let matches = loadMatchesFromStorage()
        summary = StatsSummary.build(from: matches, includeInProgress: true, perSportTeamBreakdown: true)
        rebuildIndexes()
    }

    /// Пересчитать сводку из переданного списка матчей (например, если вы работаете напрямую с репозиторием).
    public func refresh(from matches: [Match], includeInProgress: Bool = true) {
        summary = StatsSummary.build(from: matches, includeInProgress: includeInProgress, perSportTeamBreakdown: true)
        rebuildIndexes()
    }

    /// Сводка по конкретному виду спорта.
    public func overview(for sport: SportKind) -> StatsSummary.SportOverview? {
        overviewBySport[sport]
    }

    /// Рекорд команды в разрезе спорта (если сохранён хотя бы один матч).
    public func record(for teamID: UUID, sport: SportKind) -> StatsSummary.TeamRecord? {
        recordsByTeamID[teamID]?[sport]
    }

    /// Топ команд по винрейту. Если указан `sport`, фильтруем по нему.
    public func topTeamsByWinRate(limit: Int = 10, sport: SportKind? = nil, minGames: Int = 1) -> [StatsSummary.TeamRecord] {
        let all = summary.teamRecords.filter { $0.games >= minGames }
        let filtered = sport != nil ? all.filter { $0.sport == sport! } : all
        return Array(filtered.sorted { lhs, rhs in
            if lhs.winRate != rhs.winRate { return lhs.winRate > rhs.winRate }
            if lhs.games != rhs.games { return lhs.games > rhs.games }
            return lhs.teamName.localizedCaseInsensitiveCompare(rhs.teamName) == .orderedAscending
        }.prefix(max(0, limit)))
    }

    /// Команды с лучшей текущей серией побед (при равенстве — больше игр, затем имя).
    public func topWinStreaks(limit: Int = 10, sport: SportKind? = nil) -> [StatsSummary.TeamRecord] {
        let source = sport == nil ? summary.teamRecords : summary.teamRecords.filter { $0.sport == sport! }
        let winners = source.filter { $0.currentStreak > 0 }
        return Array(winners.sorted { lhs, rhs in
            if lhs.currentStreak != rhs.currentStreak { return lhs.currentStreak > rhs.currentStreak }
            if lhs.games != rhs.games { return lhs.games > rhs.games }
            return lhs.teamName.localizedCaseInsensitiveCompare(rhs.teamName) == .orderedAscending
        }.prefix(max(0, limit)))
    }

    /// Краткая витрина по спорту: количество матчей, средний тотал, доли режимов.
    public func sportDigest() -> [(sport: SportKind, matches: Int, avgTotal: Double, modeShare: [MatchRules.Mode: Double])] {
        summary.sportOverviews
            .sorted { $0.sport.label < $1.sport.label }
            .map { ($0.sport, $0.matches, $0.avgTotalPoints, $0.modeShare) }
    }

    // MARK: - Private

    private func loadMatchesFromStorage() -> [Match] {
        storage.load([Match].self,
                     for: storageKey,
                     default: [],
                     targetVersion: storageVersion,
                     allowMigrations: true)
            .dedupByID()
            .sortedByDateDesc()
    }

    private func rebuildIndexes() {
        // TeamID → (Sport → Record)
        var teamMap: [UUID: [SportKind: StatsSummary.TeamRecord]] = [:]
        for rec in summary.teamRecords {
            var bySport = teamMap[rec.teamID] ?? [:]
            bySport[rec.sport] = rec
            teamMap[rec.teamID] = bySport
        }
        self.recordsByTeamID = teamMap

        // Sport → Overview
        var sportMap: [SportKind: StatsSummary.SportOverview] = [:]
        for ov in summary.sportOverviews {
            sportMap[ov.sport] = ov
        }
        self.overviewBySport = sportMap
    }
}

// MARK: - Array helpers for matches

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
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
            return lhs.createdAt > rhs.createdAt
        }
    }
}
