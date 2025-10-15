//
//  MatchRules.swift
//  Bovanta:Sport
//
//  Created on 2025-10-14
//

import SwiftUI
import Combine

/// Unified, compact rule-set describing how a match is played and scored.
/// Covers three families:
///  - .points: race to N (optionally win-by-2)
///  - .sets: best-of S sets, each to P points (win-by-2)
///  - .timed: K periods, T seconds each (draws/OT configurable)
///
/// No заглушек — готово для использования в UI и табло.
public struct MatchRules: Codable, Hashable, Sendable {
    // MARK: - Families

    public enum Mode: String, Codable, CaseIterable, Sendable {
        case points   // до очков
        case sets     // по сетам
        case timed    // по времени (периоды)
    }

    // MARK: - Sub-Configs

    public struct PointsRule: Codable, Hashable, Sendable {
        public var target: Int            // до скольки очков (e.g., 21)
        public var winByTwo: Bool         // нужна ли разница в 2 очка
        public init(target: Int, winByTwo: Bool) {
            self.target = target
            self.winByTwo = winByTwo
        }
    }

    public struct SetsRule: Codable, Hashable, Sendable {
        public var setsToWin: Int         // сколько сетов нужно для победы (best-of)
        public var pointsPerSet: Int      // очков в сете (e.g., 25 / 11 / 21)
        public var winByTwo: Bool         // разница в 2 очка в сете
        public init(setsToWin: Int, pointsPerSet: Int, winByTwo: Bool) {
            self.setsToWin = setsToWin
            self.pointsPerSet = pointsPerSet
            self.winByTwo = winByTwo
        }
    }

    public struct TimeRule: Codable, Hashable, Sendable {
        public var periods: Int           // количество периодов / четвертей / таймов
        public var secondsPerPeriod: Int  // длительность периода в секундах
        public var allowDraw: Bool        // допускается ничья по окончании времени
        public var overtimeSeconds: Int?  // добавочное время (если не допускается ничья)
        public var stopOnScore: Bool      // останавливать ли таймер при взятии очков/голов

        public init(periods: Int,
                    secondsPerPeriod: Int,
                    allowDraw: Bool,
                    overtimeSeconds: Int? = nil,
                    stopOnScore: Bool = false) {
            self.periods = periods
            self.secondsPerPeriod = secondsPerPeriod
            self.allowDraw = allowDraw
            self.overtimeSeconds = overtimeSeconds
            self.stopOnScore = stopOnScore
        }
    }

    // MARK: - Core

    public var mode: Mode
    public var sport: SportKind

    public var points: PointsRule?
    public var sets: SetsRule?
    public var time: TimeRule?

    // Arbitrary cap for sanity (UI may use for input validation)
    public static let hardMaxPoints = 999
    public static let hardMaxSets   = 9
    public static let hardMaxPeriodSeconds = 4 * 60 * 60 // 4h

    // MARK: - Init

    public init(mode: Mode,
                sport: SportKind,
                points: PointsRule? = nil,
                sets: SetsRule? = nil,
                time: TimeRule? = nil) {
        self.mode = mode
        self.sport = sport
        self.points = points
        self.sets = sets
        self.time = time
        self = Self.validated(self)
    }

    // MARK: - Defaults by Sport

    /// Pragmatic presets per sport (can be edited in UI).
    public static func `default`(for sport: SportKind) -> MatchRules {
        switch sport {
        case .volleyball:
            return .init(mode: .sets, sport: sport,
                         sets: .init(setsToWin: 3, pointsPerSet: 25, winByTwo: true))
        case .tableTennis:
            return .init(mode: .sets, sport: sport,
                         sets: .init(setsToWin: 3, pointsPerSet: 11, winByTwo: true))
        case .badminton:
            return .init(mode: .sets, sport: sport,
                         sets: .init(setsToWin: 2, pointsPerSet: 21, winByTwo: true))
        case .tennis:
            // Упрощённая модель: сеты до 6, win-by-two
            return .init(mode: .sets, sport: sport,
                         sets: .init(setsToWin: 2, pointsPerSet: 6, winByTwo: true))
        case .football:
            // 2×45 минут, ничья разрешена
            return .init(mode: .timed, sport: sport,
                         time: .init(periods: 2, secondsPerPeriod: 45 * 60, allowDraw: true))
        case .basketball:
            // 4×10 минут, без ничьи → ОТ 5 минут
            return .init(mode: .timed, sport: sport,
                         time: .init(periods: 4, secondsPerPeriod: 10 * 60, allowDraw: false, overtimeSeconds: 5 * 60, stopOnScore: false))
        case .hockey:
            // 3×20 минут, без ничьи → ОТ 5 минут
            return .init(mode: .timed, sport: sport,
                         time: .init(periods: 3, secondsPerPeriod: 20 * 60, allowDraw: false, overtimeSeconds: 5 * 60))
        case .esportsCS:
            // До 13 раундов, без win-by-two (упрощённо)
            return .init(mode: .points, sport: sport,
                         points: .init(target: 13, winByTwo: false))
        case .esportsDota, .esportsLOL:
            // best-of-3 серии
            return .init(mode: .sets, sport: sport,
                         sets: .init(setsToWin: 2, pointsPerSet: 1, winByTwo: false))
        }
    }

    // MARK: - Validation / Sanitization

    /// Enforces sane ranges and structural consistency.
    public static func validated(_ rules: MatchRules) -> MatchRules {
        var r = rules

        func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T {
            min(max(v, lo), hi)
        }

        switch r.mode {
        case .points:
            // ensure points exists
            if r.points == nil {
                r.points = .init(target: 21, winByTwo: false)
            }
            r.sets = nil
            r.time = nil
            r.points!.target = clamp(r.points!.target, 1, hardMaxPoints)

        case .sets:
            if r.sets == nil {
                r.sets = .init(setsToWin: 2, pointsPerSet: 25, winByTwo: true)
            }
            r.points = nil
            r.time = nil
            r.sets!.setsToWin = clamp(r.sets!.setsToWin, 1, hardMaxSets)
            r.sets!.pointsPerSet = clamp(r.sets!.pointsPerSet, 1, hardMaxPoints)

        case .timed:
            if r.time == nil {
                r.time = .init(periods: 2, secondsPerPeriod: 45 * 60, allowDraw: true)
            }
            r.points = nil
            r.sets = nil
            r.time!.periods = clamp(r.time!.periods, 1, 12)
            r.time!.secondsPerPeriod = clamp(r.time!.secondsPerPeriod, 30, hardMaxPeriodSeconds)
            if r.time!.allowDraw == false {
                if let ot = r.time!.overtimeSeconds {
                    r.time!.overtimeSeconds = clamp(ot, 30, hardMaxPeriodSeconds)
                } else {
                    r.time!.overtimeSeconds = 5 * 60
                }
            } else {
                r.time!.overtimeSeconds = nil
            }
        }

        return r
    }

    // MARK: - Derived Traits (for UI/Scoreboard)

    public var usesTimer: Bool { mode == .timed }
    public var usesSets: Bool { mode == .sets }
    public var raceToPoints: Bool { mode == .points }

    /// Разрешена ли ничья в текущих правилах.
    public var allowsDraw: Bool {
        switch mode {
        case .timed: return time?.allowDraw ?? true
        case .points: return false
        case .sets: return false
        }
    }

    /// Человекочитаемое краткое описание правил (для карточек).
    public var shortDescription: String {
        switch mode {
        case .points:
            guard let p = points else { return "Race to N" }
            return p.winByTwo ? "To \(p.target) (win by 2)" : "To \(p.target)"
        case .sets:
            guard let s = sets else { return "Best-of sets" }
            let bestOf = s.setsToWin * 2 - 1
            let wb2 = s.winByTwo ? ", +2" : ""
            return "Bo\(bestOf), set \(s.pointsPerSet)\(wb2)"
        case .timed:
            guard let t = time else { return "Timed" }
            let mm = t.secondsPerPeriod / 60
            let mmStr = "\(mm)m"
            return t.allowDraw ? "\(t.periods)×\(mmStr)" : "\(t.periods)×\(mmStr) + OT"
        }
    }

    // MARK: - Builders (non-mutating helpers)

    public func withMode(_ new: Mode) -> MatchRules {
        var c = self; c.mode = new; return Self.validated(c)
    }

    public func withPoints(target: Int, winByTwo: Bool) -> MatchRules {
        var c = self; c.mode = .points; c.points = .init(target: target, winByTwo: winByTwo); return Self.validated(c)
    }

    public func withSets(setsToWin: Int, pointsPerSet: Int, winByTwo: Bool) -> MatchRules {
        var c = self; c.mode = .sets; c.sets = .init(setsToWin: setsToWin, pointsPerSet: pointsPerSet, winByTwo: winByTwo); return Self.validated(c)
    }

    public func withTime(periods: Int, secondsPerPeriod: Int, allowDraw: Bool, overtimeSeconds: Int? = nil, stopOnScore: Bool = false) -> MatchRules {
        var c = self; c.mode = .timed
        c.time = .init(periods: periods, secondsPerPeriod: secondsPerPeriod, allowDraw: allowDraw, overtimeSeconds: overtimeSeconds, stopOnScore: stopOnScore)
        return Self.validated(c)
    }
}

// MARK: - UI Utilities (optional but handy)

public extension MatchRules {
    /// Recommended default for a given sport (delegates to `.default(for:)`).
    static func recommended(for sport: SportKind) -> MatchRules {
        Self.default(for: sport)
    }

    /// A few generic presets that UI может предлагать независимо от спорта.
    static var genericPresets: [MatchRules] {
        [
            MatchRules(mode: .points, sport: .football, points: .init(target: 11, winByTwo: true)),
            MatchRules(mode: .sets, sport: .volleyball, sets: .init(setsToWin: 2, pointsPerSet: 15, winByTwo: true)),
            MatchRules(mode: .timed, sport: .basketball, time: .init(periods: 4, secondsPerPeriod: 8 * 60, allowDraw: false, overtimeSeconds: 3 * 60))
        ]
    }
}
