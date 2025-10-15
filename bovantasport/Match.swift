//
//  Match.swift
//  Bovanta:Sport
//
//  Created on 2025-10-14
//

import SwiftUI
import Combine

/// Runtime state of a single match, independent from UI.
/// Поддерживает три режима правил (points / sets / timed), undo/redo, быстрый реванш.
public struct Match: Identifiable, Codable, Hashable, Sendable {
    // MARK: - Core

    public enum Side: String, Codable, CaseIterable, Hashable, Sendable { case a, b }

    public let id: UUID
    public var createdAt: Date
    public var updatedAt: Date

    public var sport: SportKind
    public var rules: MatchRules
    public var teamA: Team
    public var teamB: Team

    // MARK: - Scoring state (mutually relevant depending on rules.mode)

    /// Simple race-to-N points
    public struct PointsState: Codable, Hashable, Sendable {
        public var scoreA: Int = 0
        public var scoreB: Int = 0
    }

    /// Set-by-set play (best-of)
    public struct SetState: Codable, Hashable, Sendable {
        public var index: Int = 0                 // 0-based current set index
        public var scoresA: [Int] = [0]           // per-set running scores
        public var scoresB: [Int] = [0]
        public var setsWonA: Int = 0              // completed sets won
        public var setsWonB: Int = 0
    }

    /// Timed play (periods/quarters/halves). Таймеров внутри нет — только счетчики.
    public struct TimeState: Codable, Hashable, Sendable {
        public var currentPeriod: Int = 0         // 0-based
        public var remainingSeconds: [Int]        // per period remaining time
        public var scoreA: Int = 0
        public var scoreB: Int = 0

        public init(periods: Int, secondsPerPeriod: Int) {
            self.currentPeriod = 0
            self.remainingSeconds = Array(repeating: max(0, secondsPerPeriod), count: max(1, periods))
            self.scoreA = 0
            self.scoreB = 0
        }
    }

    public var points: PointsState?
    public var sets: SetState?
    public var time: TimeState?

    // MARK: - Outcome

    public private(set) var winner: Side? = nil   // определяется при завершении

    // MARK: - Event Log (для историю/статистики/undo)

    public enum EventKind: String, Codable, Hashable, Sendable {
        case score            // параметр: side(+1)
        case unscore          // параметр: side(-1)
        case setWin           // параметр: side
        case periodEnd
        case periodStart
        case matchEnd         // параметр: side
        case note             // текстовая заметка
    }

    public struct Event: Codable, Hashable, Sendable, Identifiable {
        public let id: UUID
        public let at: Date
        public let kind: EventKind
        public let side: Side?
        public let value: Int?        // например +1/-1 очка, секунды и т.п.
        public let text: String?

        public init(kind: EventKind, side: Side? = nil, value: Int? = nil, text: String? = nil) {
            self.id = UUID()
            self.at = Date()
            self.kind = kind
            self.side = side
            self.value = value
            self.text = text
        }
    }

    public private(set) var events: [Event] = []

    // MARK: - Undo / Redo (моменты состояния)

    private struct Snapshot: Codable, Hashable, Sendable {
        var points: PointsState?
        var sets: SetState?
        var time: TimeState?
        var winner: Side?
        var eventsCount: Int
        var updatedAt: Date
    }

    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []

    // MARK: - Init

    public init(id: UUID = .init(),
                sport: SportKind,
                teamA: Team,
                teamB: Team,
                rules: MatchRules) {
        self.id = id
        self.createdAt = .init()
        self.updatedAt = .init()
        self.sport = sport
        self.rules = MatchRules.validated(rules)
        self.teamA = teamA
        self.teamB = teamB

        switch self.rules.mode {
        case .points:
            self.points = PointsState()
        case .sets:
            self.sets = SetState(index: 0, scoresA: [0], scoresB: [0], setsWonA: 0, setsWonB: 0)
        case .timed:
            let t = self.rules.time!
            self.time = TimeState(periods: t.periods, secondsPerPeriod: t.secondsPerPeriod)
        }
        self.winner = nil
        self.events = []
        self.undoStack = []
        self.redoStack = []
    }

    // MARK: - Public API

    /// Добавить очко стороне (или отнять, если delta отрицательная).
    public mutating func score(_ side: Side, delta: Int = 1) {
        guard delta != 0, winner == nil else { return }
        pushUndo()

        switch rules.mode {
        case .points:
            guard var s = points else { return }
            applyDelta(to: &s, side: side, delta: delta)
            points = s
            checkFinishPoints()

        case .sets:
            guard var s = sets, let cfg = rules.sets else { return }
            applyDeltaToSet(&s, cfg: cfg, side: side, delta: delta)
            sets = s

        case .timed:
            guard var t = time else { return }
            if side == .a {
                t.scoreA = max(0, t.scoreA + delta)
            } else {
                t.scoreB = max(0, t.scoreB + delta)
            }
            time = t
            events.append(.init(kind: delta > 0 ? .score : .unscore, side: side, value: delta))
        }

        updatedAt = .init()
        clearRedo()
    }

    /// Установить счёт напрямую (например, для быстрого исправления).
    public mutating func setScore(pointsA: Int, pointsB: Int) {
        guard winner == nil else { return }
        pushUndo()

        switch rules.mode {
        case .points:
            points?.scoreA = max(0, pointsA)
            points?.scoreB = max(0, pointsB)
            events.append(.init(kind: .note, text: "Score set to \(pointsA):\(pointsB)"))
            checkFinishPoints()
        case .sets:
            if var s = sets {
                if s.index < s.scoresA.count {
                    s.scoresA[s.index] = max(0, pointsA)
                }
                if s.index < s.scoresB.count {
                    s.scoresB[s.index] = max(0, pointsB)
                }
                sets = s
                events.append(.init(kind: .note, text: "Set score set to \(pointsA):\(pointsB)"))
            }
        case .timed:
            if var t = time {
                t.scoreA = max(0, pointsA)
                t.scoreB = max(0, pointsB)
                time = t
                events.append(.init(kind: .note, text: "Timed score set to \(pointsA):\(pointsB)"))
            }
        }

        updatedAt = .init()
        clearRedo()
    }

    /// Тик таймера (уменьшает оставшееся время). UI обязан вызывать это по своему таймеру.
    public mutating func tick(seconds: Int = 1) {
        guard seconds > 0, winner == nil, rules.mode == .timed, var t = time else { return }
        guard t.currentPeriod < t.remainingSeconds.count else { return }

        pushUndo()

        var remain = t.remainingSeconds[t.currentPeriod]
        remain = max(0, remain - seconds)
        t.remainingSeconds[t.currentPeriod] = remain

        if remain == 0 {
            periodDidEnd(&t)
        } else if rules.time?.stopOnScore == true {
            // ничего — остановка таймера реализуется в UI уровнем
        }

        time = t
        updatedAt = .init()
        clearRedo()
    }

    /// Принудительно завершить текущий период (например, по свистку).
    public mutating func endPeriod() {
        guard rules.mode == .timed, var t = time, winner == nil else { return }
        pushUndo()
        periodDidEnd(&t, force: true)
        time = t
        updatedAt = .init()
        clearRedo()
    }

    /// Добавить текстовую заметку в лог.
    public mutating func addNote(_ text: String) {
        pushUndo()
        events.append(.init(kind: .note, text: text))
        updatedAt = .init()
        clearRedo()
    }

    /// Мягкий сброс текущего сета (в режиме sets) — начать сет заново.
    public mutating func resetCurrentSet() {
        guard rules.mode == .sets, var s = sets, winner == nil else { return }
        pushUndo()
        s.scoresA[s.index] = 0
        s.scoresB[s.index] = 0
        sets = s
        events.append(.init(kind: .note, text: "Current set reset"))
        updatedAt = .init()
        clearRedo()
    }

    /// Полный сброс матча (сохранит команды/правила).
    public mutating func resetAll() {
        pushUndo()
        switch rules.mode {
        case .points:
            points = .init()
        case .sets:
            sets = .init(index: 0, scoresA: [0], scoresB: [0], setsWonA: 0, setsWonB: 0)
        case .timed:
            if let cfg = rules.time {
                time = .init(periods: cfg.periods, secondsPerPeriod: cfg.secondsPerPeriod)
            }
        }
        winner = nil
        events.removeAll()
        updatedAt = .init()
        clearRedo()
    }

    /// Создать реванш на тех же правилах и командах (чистое состояние).
    public func rematch(swapped: Bool = false) -> Match {
        Match(sport: sport,
              teamA: swapped ? teamB : teamA,
              teamB: swapped ? teamA : teamB,
              rules: rules)
    }

    // MARK: - Derived values

    public var isFinished: Bool { winner != nil }

    public var currentScoreTuple: (a: Int, b: Int) {
        switch rules.mode {
        case .points:
            return (points?.scoreA ?? 0, points?.scoreB ?? 0)
        case .sets:
            if let s = sets, s.index < s.scoresA.count, s.index < s.scoresB.count {
                return (s.scoresA[s.index], s.scoresB[s.index])
            }
            return (0, 0)
        case .timed:
            return (time?.scoreA ?? 0, time?.scoreB ?? 0)
        }
    }

    public var progressDescription: String {
        switch rules.mode {
        case .points:
            let p = points ?? .init()
            return "\(p.scoreA) : \(p.scoreB)"
        case .sets:
            if let s = sets, let cfg = rules.sets {
                let setNo = s.index + 1
                return "Set \(setNo) — \(s.scoresA[s.index]) : \(s.scoresB[s.index])  (W \(s.setsWonA)–\(s.setsWonB), Bo\(cfg.setsToWin*2-1))"
            }
            return "Sets"
        case .timed:
            if let t = time, let cfg = rules.time {
                let mm = max(0, t.remainingSeconds[safe: t.currentPeriod] ?? 0) / 60
                let ss = max(0, t.remainingSeconds[safe: t.currentPeriod] ?? 0) % 60
                return "P\(t.currentPeriod + 1)/\(cfg.periods)  \(String(format: "%02d:%02d", mm, ss)) — \(t.scoreA) : \(t.scoreB)"
            }
            return "Timed"
        }
    }

    // MARK: - Undo/Redo

    public mutating func undo() {
        guard let snap = undoStack.popLast() else { return }
        let current = makeSnapshot()
        redoStack.append(current)

        self.points = snap.points
        self.sets = snap.sets
        self.time = snap.time
        self.winner = snap.winner
        if events.count > snap.eventsCount {
            events.removeLast(events.count - snap.eventsCount)
        }
        self.updatedAt = snap.updatedAt
    }

    public mutating func redo() {
        guard let snap = redoStack.popLast() else { return }
        pushUndo()
        self.points = snap.points
        self.sets = snap.sets
        self.time = snap.time
        self.winner = snap.winner
        if events.count > snap.eventsCount {
            events.removeLast(events.count - snap.eventsCount)
        }
        self.updatedAt = snap.updatedAt
    }

    // MARK: - Private helpers

    private mutating func pushUndo() {
        undoStack.append(makeSnapshot())
        if undoStack.count > 100 { undoStack.removeFirst() } // простая защита
    }

    private mutating func clearRedo() {
        redoStack.removeAll()
    }

    private func makeSnapshot() -> Snapshot {
        Snapshot(points: points,
                 sets: sets,
                 time: time,
                 winner: winner,
                 eventsCount: events.count,
                 updatedAt: updatedAt)
    }

    private mutating func applyDelta(to s: inout PointsState, side: Side, delta: Int) {
        if side == .a {
            s.scoreA = max(0, s.scoreA + delta)
        } else {
            s.scoreB = max(0, s.scoreB + delta)
        }
        events.append(.init(kind: delta > 0 ? .score : .unscore, side: side, value: delta))
    }

    private mutating func checkFinishPoints() {
        guard let cfg = rules.points, var s = points, winner == nil else { return }
        let a = s.scoreA, b = s.scoreB
        if cfg.winByTwo {
            if a >= cfg.target || b >= cfg.target {
                let diff = abs(a - b)
                if diff >= 2 {
                    winner = a > b ? .a : .b
                }
            }
        } else {
            if a >= cfg.target || b >= cfg.target {
                winner = a > b ? .a : .b
            }
        }
        if let w = winner {
            events.append(.init(kind: .matchEnd, side: w))
        }
        points = s
    }

    private mutating func applyDeltaToSet(_ s: inout SetState, cfg: MatchRules.SetsRule, side: Side, delta: Int) {
        ensureSetArrays(&s)

        if side == .a {
            s.scoresA[s.index] = max(0, s.scoresA[s.index] + delta)
        } else {
            s.scoresB[s.index] = max(0, s.scoresB[s.index] + delta)
        }
        events.append(.init(kind: delta > 0 ? .score : .unscore, side: side, value: delta))

        // Проверяем завершение сета
        let a = s.scoresA[s.index], b = s.scoresB[s.index]
        let setFinished: Bool = {
            if cfg.winByTwo {
                if a >= cfg.pointsPerSet || b >= cfg.pointsPerSet {
                    return abs(a - b) >= 2
                }
                return false
            } else {
                return a >= cfg.pointsPerSet || b >= cfg.pointsPerSet
            }
        }()

        if setFinished {
            if a > b { s.setsWonA += 1 } else { s.setsWonB += 1 }
            events.append(.init(kind: .setWin, side: a > b ? .a : .b))

            // Проверяем победу в матче
            if s.setsWonA >= cfg.setsToWin {
                winner = .a
                events.append(.init(kind: .matchEnd, side: .a))
            } else if s.setsWonB >= cfg.setsToWin {
                winner = .b
                events.append(.init(kind: .matchEnd, side: .b))
            } else {
                // Готовим следующий сет
                s.index += 1
                s.scoresA.append(0)
                s.scoresB.append(0)
            }
        }
    }

    private mutating func ensureSetArrays(_ s: inout SetState) {
        if s.index >= s.scoresA.count { s.scoresA.append(0) }
        if s.index >= s.scoresB.count { s.scoresB.append(0) }
    }

    private mutating func periodDidEnd(_ t: inout TimeState, force: Bool = false) {
        guard let cfg = rules.time else { return }
        // Закрываем текущий период
        events.append(.init(kind: .periodEnd, value: t.currentPeriod))

        if t.currentPeriod + 1 < cfg.periods {
            // Следующий период
            t.currentPeriod += 1
            events.append(.init(kind: .periodStart, value: t.currentPeriod))
        } else {
            // Время основного матча истекло
            if cfg.allowDraw {
                // Ничья разрешена → победителя нет
                if t.scoreA != t.scoreB {
                    winner = t.scoreA > t.scoreB ? .a : .b
                    events.append(.init(kind: .matchEnd, side: winner))
                } else {
                    // ничья — winner остаётся nil
                }
            } else {
                // Без ничьи — добавляем ОТ, если требуется
                if t.scoreA == t.scoreB {
                    let ot = max(30, cfg.overtimeSeconds ?? 60)
                    t.remainingSeconds.append(ot)
                    t.currentPeriod += 1
                    events.append(.init(kind: .periodStart, value: t.currentPeriod))
                } else {
                    winner = t.scoreA > t.scoreB ? .a : .b
                    events.append(.init(kind: .matchEnd, side: winner))
                }
            }
        }
    }
}

// MARK: - Safe index access

private extension Array {
    subscript (safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
