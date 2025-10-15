//
//  ScoreboardScreen.swift
//  Bovanta:Sport
//
//  Created on 2025-10-14
//

import SwiftUI
import Combine

/// Живое табло матча: счёт, сеты/периоды, таймер (локальный), undo/redo, быстрые действия.
/// Работает с реальным `MatchesRepository` — никаких заглушек.
public struct ScoreboardScreen: View {
    // MARK: - Env
    @EnvironmentObject private var theme: AppTheme
    @EnvironmentObject private var haptics: HapticsManager
    @EnvironmentObject private var matchesRepo: MatchesRepository
    @Environment(\.dismiss) private var dismiss

    // MARK: - Input
    public let matchID: UUID

    // MARK: - State
    @State private var match: Match?
    @State private var isTimerRunning: Bool = false
    @State private var timerCancellable: AnyCancellable?
    @State private var noteDraft: String = ""
    @State private var showNoteField: Bool = false
    @State private var showResetAlert: Bool = false

    // MARK: - Init
    public init(matchID: UUID) {
        self.matchID = matchID
    }

    // MARK: - Body
    public var body: some View {
        Group {
            if let m = match {
                content(for: m)
            } else {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Loading match…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.background.ignoresSafeArea())
            }
        }
        .onAppear {
            reload()
        }
        .onDisappear {
            stopTimer()
        }
        .onReceive(matchesRepo.$history) { _ in
            // Подхватываем изменения из репозитория
            if let updated = matchesRepo.match(by: matchID) {
                self.match = updated
                // Останавливаем таймер, если матч завершён
                if updated.isFinished { stopTimer() }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    _ = matchesRepo.undo(matchID: matchID)
                    haptics.soft()
                } label: {
                    Image(systemName: "arrow.uturn.backward.circle")
                }
                .disabled(!(match != nil))

                Button {
                    _ = matchesRepo.redo(matchID: matchID)
                    haptics.soft()
                } label: {
                    Image(systemName: "arrow.uturn.forward.circle")
                }
                .disabled(!(match != nil))

                Menu {
                    Button(role: .destructive) {
                        showResetAlert = true
                    } label: {
                        Label("Reset match", systemImage: "arrow.counterclockwise.circle")
                    }
                    Button {
                        showNoteField.toggle()
                        haptics.select()
                    } label: {
                        Label("Add note", systemImage: "note.text")
                    }
                    if (match?.rules.mode == .timed) == true {
                        Divider()
                        Button {
                            endPeriod()
                        } label: {
                            Label("End period", systemImage: "flag.checkered")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("Reset match?", isPresented: $showResetAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) { resetAll() }
        } message: {
            Text("Счёт, сеты и таймер будут сброшены. Команды и правила останутся.")
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Content

    @ViewBuilder
    private func content(for m: Match) -> some View {
        VStack(spacing: 16) {
            header(m)

            switch m.rules.mode {
            case .points:
                pointsBoard(m)
            case .sets:
                setsBoard(m)
            case .timed:
                timedBoard(m)
            }

            if showNoteField {
                noteComposer()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(theme.background.ignoresSafeArea())
    }

    // MARK: - Header

    private func header(_ m: Match) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                teamBadge(m.teamA)
                VStack(spacing: 2) {
                    Text("vs")
                        .font(theme.typography.titleSmall)
                        .foregroundColor(theme.palette.textSecondary)
                    HStack(spacing: 6) {
                        m.sport.icon
                        Text(m.sport.label)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(m.sport.accent)
                }
                teamBadge(m.teamB)
                Spacer()
            }

            Text(statusLine(m))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(theme.palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func teamBadge(_ t: Team) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(ColorSwatches.ringGradient(t.color)).frame(width: 40, height: 40)
                t.badge.resizable().scaledToFit().frame(width: 18, height: 18).foregroundStyle(t.foregroundOnColor)
            }
            Text(t.name)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(theme.palette.textPrimary)
                .lineLimit(1)
        }
    }

    private func statusLine(_ m: Match) -> String {
        if m.isFinished {
            let w = (m.winner == .a) ? m.teamA.name : (m.winner == .b ? m.teamB.name : "Draw")
            return "Finished • Winner: \(w)"
        }
        return m.progressDescription
    }

    // MARK: - Points mode

    private func pointsBoard(_ m: Match) -> some View {
        VStack(spacing: 14) {
            scoreRow(a: m.currentScoreTuple.a, b: m.currentScoreTuple.b, accent: m.sport.accent)

            HStack(spacing: 12) {
                sideControls(side: .a, accent: m.teamA.color) { delta in
                    applyScore(side: .a, delta: delta)
                }
                sideControls(side: .b, accent: m.teamB.color) { delta in
                    applyScore(side: .b, delta: delta)
                }
            }

            ruleSummary(m.rules)
        }
    }

    // MARK: - Sets mode

    private func setsBoard(_ m: Match) -> some View {
        VStack(spacing: 12) {
            scoreRow(a: m.currentScoreTuple.a, b: m.currentScoreTuple.b, accent: m.sport.accent)

            HStack(spacing: 12) {
                sideControls(side: .a, accent: m.teamA.color) { delta in
                    applyScore(side: .a, delta: delta)
                }
                sideControls(side: .b, accent: m.teamB.color) { delta in
                    applyScore(side: .b, delta: delta)
                }
            }

            if let s = m.sets {
                setsStrip(s, accent: m.sport.accent)
                Button {
                    _ = matchesRepo.resetCurrentSet(matchID: matchID)
                    haptics.warning()
                } label: {
                    Label("Reset current set", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .tint(m.sport.accent)
            }

            ruleSummary(m.rules)
        }
    }

    private func setsStrip(_ s: Match.SetState, accent: Color) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(0..<max(s.scoresA.count, s.scoresB.count), id: \.self) { i in
                    let a = s.scoresA[safe: i] ?? 0
                    let b = s.scoresB[safe: i] ?? 0
                    VStack(spacing: 4) {
                        Text("Set \(i + 1)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                        HStack(spacing: 8) {
                            Text("\(a)").font(.system(size: 16, weight: .bold, design: .rounded))
                            Text(":").font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundColor(.secondary)
                            Text("\(b)").font(.system(size: 16, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(theme.palette.textPrimary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(ColorSwatches.softVerticalGradient(i == s.index ? accent : theme.palette.secondary))
                    .foregroundColor(ColorSwatches.bestTextColor(on: i == s.index ? accent : theme.palette.secondary))
                    .cornerRadius(10)
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Timed mode

    private func timedBoard(_ m: Match) -> some View {
        VStack(spacing: 14) {
            // Timer face
            if let t = m.time, let cfg = m.rules.time {
                let remaining = (t.remainingSeconds[safe: t.currentPeriod] ?? cfg.secondsPerPeriod)
                TimerFace(currentPeriod: t.currentPeriod + 1,
                          totalPeriods: t.remainingSeconds.count,
                          seconds: remaining,
                          accent: m.sport.accent)

                HStack(spacing: 10) {
                    Button {
                        adjustTime(-10)
                    } label: {
                        Label("-10s", systemImage: "gobackward.10")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        toggleTimer()
                    } label: {
                        Label(isTimerRunning ? "Pause" : "Start", systemImage: isTimerRunning ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(m.sport.accent)

                    Button {
                        adjustTime(+10)
                    } label: {
                        Label("+10s", systemImage: "goforward.10")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        endPeriod()
                    } label: {
                        Label("End", systemImage: "flag.checkered")
                    }
                    .buttonStyle(.bordered)
                }
            }

            // Score digits
            scoreRow(a: m.currentScoreTuple.a, b: m.currentScoreTuple.b, accent: m.sport.accent)

            HStack(spacing: 12) {
                sideControls(side: .a, accent: m.teamA.color) { delta in
                    applyScore(side: .a, delta: delta)
                    if m.rules.time?.stopOnScore == true { pauseTimer() }
                }
                sideControls(side: .b, accent: m.teamB.color) { delta in
                    applyScore(side: .b, delta: delta)
                    if m.rules.time?.stopOnScore == true { pauseTimer() }
                }
            }

            ruleSummary(m.rules)
        }
    }

    // MARK: - Subviews

    private func scoreRow(a: Int, b: Int, accent: Color) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 16) {
            Text("\(a)")
                .font(.system(size: 54, weight: .bold, design: .rounded))
                .foregroundColor(theme.palette.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(theme.palette.surface.cornerRadius(12))

            Text(":")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(accent)

            Text("\(b)")
                .font(.system(size: 54, weight: .bold, design: .rounded))
                .foregroundColor(theme.palette.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(theme.palette.surface.cornerRadius(12))
        }
    }

    private func sideControls(side: Match.Side, accent: Color, onDelta: @escaping (Int) -> Void) -> some View {
        VStack(spacing: 8) {
            Button {
                onDelta(+1)
            } label: {
                Label("+1", systemImage: "plus.circle.fill")
                    .font(.title3)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)

            HStack(spacing: 8) {
                Button {
                    onDelta(+2)
                } label: {
                    Label("+2", systemImage: "plus")
                }
                .buttonStyle(.bordered)

                Button {
                    onDelta(-1)
                } label: {
                    Label("-1", systemImage: "minus")
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func ruleSummary(_ rules: MatchRules) -> some View {
        HStack {
            Image(systemName: rules.mode == .timed ? "timer" : (rules.mode == .sets ? "square.grid.2x2" : "number"))
            Text(rules.shortDescription)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(theme.palette.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }

    private func noteComposer() -> some View {
        HStack(spacing: 8) {
            Image(systemName: "note.text").foregroundStyle(.secondary)
            TextField("Add a note…", text: $noteDraft)
            Button {
                let txt = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !txt.isEmpty else { return }
                _ = matchesRepo.addNote(matchID: matchID, text: txt)
                noteDraft = ""
                showNoteField = false
                haptics.light()
            } label: {
                Image(systemName: "paperplane.fill")
            }
            .buttonStyle(.plain)

            Button {
                noteDraft = ""
                showNoteField = false
                haptics.soft()
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(theme.palette.surface.cornerRadius(10))
    }

    // MARK: - Actions

    private func reload() {
        if let m = matchesRepo.match(by: matchID) {
            self.match = m
            if m.rules.mode != .timed { stopTimer() }
        }
    }

    private func applyScore(side: Match.Side, delta: Int) {
        guard match?.isFinished == false else { return }
        _ = matchesRepo.score(matchID: matchID, side: side, delta: delta)
        if delta > 0 {
            delta >= 2 ? haptics.heavy() : haptics.light()
        } else {
            haptics.rigid()
        }
    }

    private func resetAll() {
        stopTimer()
        _ = matchesRepo.resetAll(matchID: matchID)
        haptics.warning()
    }

    // Timer controls (UI-driven)

    private func toggleTimer() {
        if isTimerRunning { pauseTimer() } else { startTimer() }
    }

    private func startTimer() {
        guard let m = match, m.rules.mode == .timed, !m.isFinished else { return }
        isTimerRunning = true
        haptics.select()
        timerCancellable?.cancel()
        // 1 Hz tick on main run loop
        timerCancellable = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                _ = matchesRepo.tick(matchID: matchID, seconds: 1)
                // Repo onReceive will refresh `match` and stop timer if finished
                haptics.soft()
            }
    }

    private func pauseTimer() {
        isTimerRunning = false
        timerCancellable?.cancel()
        timerCancellable = nil
        haptics.soft()
    }

    private func stopTimer() {
        isTimerRunning = false
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    private func adjustTime(_ deltaSeconds: Int) {
        // Нет прямого API изменять секундомер, поэтому делаем "симулированный" тик:
        // минус — это просто уменьшаем через tick положительным числом в несколько шагов,
        // плюс — добавим отрицательным шагом невозможно; используем небольшой хак:
        // добавление времени реализуем как endPeriod отменён? Нельзя. Поэтому делаем заметку.
        // Честное добавление секунд потребует расширить Match API. Мы ограничимся уменьшением,
        // а для увеличения — запишем заметку, чтобы избежать рассинхронизации.
        guard let m = match, m.rules.mode == .timed, !m.isFinished else { return }
        if deltaSeconds < 0 {
            let secs = abs(deltaSeconds)
            _ = matchesRepo.tick(matchID: matchID, seconds: secs) // тикаем быстрее (репо оперирует целыми секундами)
            haptics.rigid()
        } else if deltaSeconds > 0 {
            // Прозрачно сообщим пользователю — функционал увеличения времени отсутствует в модели.
            _ = matchesRepo.addNote(matchID: matchID, text: "Requested +\(deltaSeconds)s (time increase not supported)")
            haptics.warning()
        }
    }

    private func endPeriod() {
        _ = matchesRepo.endPeriod(matchID: matchID)
        haptics.light()
    }
}

// MARK: - Timer Face

private struct TimerFace: View {
    @EnvironmentObject private var theme: AppTheme
    let currentPeriod: Int
    let totalPeriods: Int
    let seconds: Int
    let accent: Color

    var body: some View {
        VStack(spacing: 6) {
            Text("Period \(currentPeriod)/\(totalPeriods)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(theme.palette.textSecondary)

            Text(timeString)
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(ColorSwatches.bestTextColor(on: accent))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(ColorSwatches.softVerticalGradient(accent))
                .cornerRadius(10)
                .shadow(color: ColorSwatches.shadow(for: accent), radius: 6, x: 0, y: 3)
        }
    }

    private var timeString: String {
        let mm = max(0, seconds) / 60
        let ss = max(0, seconds) % 60
        return String(format: "%02d:%02d", mm, ss)
    }
}

// MARK: - Safe subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
