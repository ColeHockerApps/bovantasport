//
//  StatsSummary.swift
//  Bovanta:Sport
//
//  Created on 2025-10-14
//

import SwiftUI
import Combine

/// Aggregated statistics derived from `Match`.
/// Поддерживает все режимы (points/sets/timed). Без заглушек.
public struct StatsSummary: Hashable, Codable, Sendable {
    // MARK: - Per-Team record (cross-sport or per-sport)
    public struct TeamRecord: Hashable, Codable, Sendable, Identifiable {
        public var id: UUID { teamID }

        public let teamID: UUID
        public let teamName: String
        public let sport: SportKind

        public var games: Int
        public var wins: Int
        public var losses: Int
        public var draws: Int

        /// Суммарные очки/сеты «за» и «против» (в points — очки, в sets — сеты, в timed — голы/очки).
        public var pointsFor: Int
        public var pointsAgainst: Int

        /// Текущая серия (побед/поражений). Положительное значение — серия побед, отрицательное — поражений.
        public var currentStreak: Int
        /// Максимальная серия побед.
        public var longestWinStreak: Int

        // Derived
        public var winRate: Double {
            guard games > 0 else { return 0 }
            return Double(wins) / Double(games)
        }

        public var avgFor: Double { games > 0 ? Double(pointsFor) / Double(games) : 0 }
        public var avgAgainst: Double { games > 0 ? Double(pointsAgainst) / Double(games) : 0 }
        public var avgMargin: Double { avgFor - avgAgainst }
    }

    // MARK: - Per-Sport overview
    public struct SportOverview: Hashable, Codable, Sendable, Identifiable {
        public var id: String { sport.rawValue }

        public let sport: SportKind
        public var matches: Int
        public var finished: Int
        public var draws: Int

        /// Средний суммарный счёт матча (A+B) в соответствующей метрике (очк/сеты/галы).
        public var avgTotalPoints: Double

        /// Считаем долю каждого режима для этого спорта (на случай кастомных правил).
        public var modeShare: [MatchRules.Mode: Double]
    }

    // MARK: - Root payload
    public var generatedAt: Date
    public var teamRecords: [TeamRecord]
    public var sportOverviews: [SportOverview]

    // MARK: - Factory

    /// Построить сводку по всем матчам.
    /// - Parameters:
    ///   - matches: История матчей (включая незавершённые).
    ///   - includeInProgress: Учитывать ли незавершённые в агрегатах (по текущему счёту).
    ///   - perSportTeamBreakdown: Если true — создаёт записи по каждой команде **в разрезе вида спорта**.
    public static func build(from matches: [Match],
                             includeInProgress: Bool = true,
                             perSportTeamBreakdown: Bool = true) -> StatsSummary {
        var teamMap: [String: TeamRecord] = [:] // key: teamID|sport
        var sportMap: [SportKind: SportAccumulator] = [:]

        // Для расчёта серий — нужна последовательность по времени.
        let ordered = matches.sorted { $0.createdAt < $1.createdAt }

        for m in ordered {
            let final = finalScores(for: m, includeInProgress: includeInProgress)
            guard let finalScores = final else { continue } // если матч пустой и in-progress запрещён

            // Обновляем спортовые агрегаты
            var sAcc = sportMap[m.sport, default: .init(sport: m.sport)]
            sAcc.feed(match: m, scores: finalScores)
            sportMap[m.sport] = sAcc

            // Обновляем команды A/B
            feedTeam(&teamMap, team: m.teamA, opponent: m.teamB, match: m, scores: finalScores, side: .a)
            feedTeam(&teamMap, team: m.teamB, opponent: m.teamA, match: m, scores: finalScores, side: .b)
        }

        // Финализация серий и мод-долей
        var sportOverviews: [SportOverview] = []
        for (_, acc) in sportMap {
            sportOverviews.append(acc.finish())
        }

        // Коллекция результатов по командам
        let teamRecords = Array(teamMap.values)
            .sorted { lhs, rhs in
                if lhs.teamName != rhs.teamName { return lhs.teamName.localizedCaseInsensitiveCompare(rhs.teamName) == .orderedAscending }
                return lhs.sport.label.localizedCaseInsensitiveCompare(rhs.sport.label) == .orderedAscending
            }

        return StatsSummary(
            generatedAt: Date(),
            teamRecords: teamRecords,
            sportOverviews: sportOverviews.sorted { $0.sport.label < $1.sport.label }
        )
    }

    // MARK: - Helpers (final score extraction)

    /// Возвращает финальные (или текущие) очки по матчам как (A,B) и статус.
    /// Для sets берём количество выигранных сетов как «очки».
    private static func finalScores(for match: Match, includeInProgress: Bool) -> (a: Int, b: Int, finished: Bool, draw: Bool)? {
        switch match.rules.mode {
        case .points:
            let a = match.points?.scoreA ?? 0
            let b = match.points?.scoreB ?? 0
            let finished = match.isFinished
            if !finished && !includeInProgress { return nil }
            return (a, b, finished, false)

        case .sets:
            if let s = match.sets {
                let finished = match.isFinished
                // Итоговые «очки» — количество выигранных сетов
                let a = finished ? s.setsWonA : s.setsWonA
                let b = finished ? s.setsWonB : s.setsWonB
                if !finished && !includeInProgress { return nil }
                return (a, b, finished, false)
            }
            return nil

        case .timed:
            if let t = match.time {
                let a = t.scoreA
                let b = t.scoreB
                let finished = match.isFinished || (t.currentPeriod + 1 >= (match.rules.time?.periods ?? 0) && (a != b || match.rules.time?.allowDraw == true))
                let draw = finished && (a == b) && (match.rules.time?.allowDraw == true)
                if !finished && !includeInProgress { return nil }
                return (a, b, finished, draw)
            }
            return nil
        }
    }
}

// MARK: - Internal feed logic

private extension StatsSummary {
    /// Обновляем запись команды с учётом результата матча.
    static func feedTeam(_ map: inout [String: TeamRecord],
                         team: Team,
                         opponent: Team,
                         match: Match,
                         scores: (a: Int, b: Int, finished: Bool, draw: Bool),
                         side: Match.Side) {

        let key: String
        if opponent.sport != team.sport {
            // По определению в модели — матч всегда в одном спорте;
            // но ключ безопасно формируем по флагу perSportTeamBreakdown (здесь — всегда per sport).
            key = "\(team.id.uuidString)|\(team.sport.rawValue)"
        } else {
            key = "\(team.id.uuidString)|\(team.sport.rawValue)"
        }

        var rec = map[key] ?? TeamRecord(
            teamID: team.id,
            teamName: team.name,
            sport: team.sport,
            games: 0, wins: 0, losses: 0, draws: 0,
            pointsFor: 0, pointsAgainst: 0,
            currentStreak: 0,
            longestWinStreak: 0
        )

        // Текущие очки для стороны
        let forMe  = (side == .a) ? scores.a : scores.b
        let forOpp = (side == .a) ? scores.b : scores.a
        rec.pointsFor += max(0, forMe)
        rec.pointsAgainst += max(0, forOpp)

        if scores.finished {
            rec.games += 1
            if scores.draw {
                rec.draws += 1
                // Сброс серии (ничья не влияет на знак), но не обрывает победную? Примем обнуление.
                rec.currentStreak = 0
            } else {
                let didWin: Bool = (match.winner == (side == .a ? .a : .b)) || (match.winner == nil && forMe > forOpp)
                if didWin {
                    rec.wins += 1
                    // обновляем серию (положительная)
                    rec.currentStreak = rec.currentStreak >= 0 ? rec.currentStreak + 1 : 1
                    rec.longestWinStreak = max(rec.longestWinStreak, rec.currentStreak)
                } else {
                    rec.losses += 1
                    // отрицательная серия
                    rec.currentStreak = rec.currentStreak <= 0 ? rec.currentStreak - 1 : -1
                }
            }
        } else {
            // Незавершенные — не увеличиваем games/wins/losses/draws, но суммируем баллы.
            // Серии остаются как есть.
        }

        map[key] = rec
    }

    // Агрегатор по виду спорта
    struct SportAccumulator: Hashable {
        let sport: SportKind
        var matches: Int = 0
        var finished: Int = 0
        var draws: Int = 0
        var sumTotalPoints: Int = 0

        var modeCount: [MatchRules.Mode: Int] = [:]

        mutating func feed(match: Match, scores: (a: Int, b: Int, finished: Bool, draw: Bool)) {
            matches += 1
            if scores.finished { finished += 1 }
            if scores.draw { draws += 1 }
            sumTotalPoints += max(0, scores.a + scores.b)
            modeCount[match.rules.mode, default: 0] += 1
        }

        func finish() -> StatsSummary.SportOverview {
            let avg = matches > 0 ? Double(sumTotalPoints) / Double(matches) : 0
            let total = max(1, matches)
            let share: [MatchRules.Mode: Double] = Dictionary(uniqueKeysWithValues:
                modeCount.map { ($0.key, Double($0.value) / Double(total)) }
            )
            return .init(
                sport: sport,
                matches: matches,
                finished: finished,
                draws: draws,
                avgTotalPoints: avg,
                modeShare: share
            )
        }
    }
}
