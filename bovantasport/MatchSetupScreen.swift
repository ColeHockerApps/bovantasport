//
//  MatchSetupScreen.swift
//  Bovanta:Sport
//
//  Created on 2025-10-14
//

import SwiftUI
import Combine

/// Экран настройки матча: выбор спорта, команд A/B, правил и быстрых пресетов.
/// Без заглушек — кнопка Start реально создаёт матч в MatchesRepository и закрывает экран.
public struct MatchSetupScreen: View {
    // MARK: - Env
    @EnvironmentObject private var theme: AppTheme
    @EnvironmentObject private var haptics: HapticsManager
    @EnvironmentObject private var teamsRepo: TeamsRepository
    @EnvironmentObject private var matchesRepo: MatchesRepository
    @Environment(\.dismiss) private var dismiss

    // MARK: - State
    @State private var sport: SportKind = .football
    @State private var teamA: Team? = nil
    @State private var teamB: Team? = nil
    @State private var rules: MatchRules = MatchRules.default(for: .football)

    @State private var showTeamPickerA: Bool = false
    @State private var showTeamPickerB: Bool = false
    @State private var errorText: String? = nil
    @State private var didCreateMatch: Bool = false

    public init() {}

    // MARK: - Body
    public var body: some View {
        Form {
            Section {
                sportSelector
            } header: {
                Text("Sport")
            }
            .listRowBackground(theme.palette.surface)

            Section {
                teamPickers
            } header: {
                Text("Teams")
            } footer: {
                if let a = teamA, let b = teamB, a.id == b.id {
                    Text("Команды A и B не могут совпадать. Выберите разные команды.")
                        .foregroundColor(theme.palette.danger)
                }
            }
            .listRowBackground(theme.palette.surface)

            Section {
                PresetsRow(sport: sport) { preset in
                    rules = preset
                    haptics.select()
                }
                RulesEditor(rules: $rules)
            } header: {
                Text("Rules")
            } footer: {
                Text(rules.shortDescription)
                    .foregroundColor(theme.palette.textSecondary)
            }
            .listRowBackground(theme.palette.surface)

            Section {
                Button {
                    startMatch()
                } label: {
                    HStack {
                        Spacer()
                        Label("Start Match", systemImage: "play.fill")
                            .font(theme.typography.titleSmall)
                        Spacer()
                    }
                    .padding(.vertical, 2)
                }
                .buttonStyle(.borderedProminent)
                .tint(sport.accent)
                .disabled(!canStart)
            }
            .listRowBackground(theme.palette.surface)
        }
        .scrollContentBackground(.hidden)
        .background(theme.background.ignoresSafeArea())
        .navigationTitle("Match Setup")
        .onAppear {
            // Инициализация базовых значений
            rules = MatchRules.default(for: sport)
            preloadTeamsIfPossible()
        }
        .sheet(isPresented: $showTeamPickerA) {
            TeamPickerSheet(
                title: "Select Team A",
                sport: sport,
                selected: teamA?.id,
                createQuick: { quickTeamName() },
                onPick: { picked in
                    teamA = picked
                    if teamB?.id == picked.id { teamB = nil }
                    haptics.select()
                }
            )
            .environmentObject(theme)
            .environmentObject(teamsRepo)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showTeamPickerB) {
            TeamPickerSheet(
                title: "Select Team B",
                sport: sport,
                selected: teamB?.id,
                createQuick: { quickTeamName(b: true) },
                onPick: { picked in
                    teamB = picked
                    if teamA?.id == picked.id { teamA = nil }
                    haptics.select()
                }
            )
            .environmentObject(theme)
            .environmentObject(teamsRepo)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .alert("Cannot start", isPresented: .constant(errorText != nil), actions: {
            Button("OK") { errorText = nil }
        }, message: {
            Text(errorText ?? "")
        })
        .alert("Match created", isPresented: $didCreateMatch) {
            Button("OK") { dismiss() }
        } message: {
            Text("Матч добавлен в историю. Удачной игры!")
        }
    }

    // MARK: - Subviews

    private var sportSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SportKind.allCases, id: \.self) { kind in
                    SportChip(kind: kind, selected: kind == sport)
                        .onTapGesture {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                                sport = kind
                                rules = MatchRules.default(for: kind)
                                // обновим отбор команд под спорт
                                if teamA?.sport != sport { teamA = nil }
                                if teamB?.sport != sport { teamB = nil }
                            }
                            haptics.select()
                        }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var teamPickers: some View {
        VStack(spacing: 10) {
            teamPickerRow(side: "A", team: teamA, tap: {
                showTeamPickerA = true
            }, replaceWithQuick: {
                teamA = autoCreateTeam(name: quickTeamName())
            })

            teamPickerRow(side: "B", team: teamB, tap: {
                showTeamPickerB = true
            }, replaceWithQuick: {
                teamB = autoCreateTeam(name: quickTeamName(b: true))
            })
        }
    }

    private func teamPickerRow(side: String, team: Team?, tap: @escaping () -> Void, replaceWithQuick: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(ColorSwatches.ringGradient(team?.color ?? sport.accent))
                        .frame(width: 40, height: 40)
                    if let t = team {
                        t.badge
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                            .foregroundStyle(t.foregroundOnColor)
                    } else {
                        Text(side)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(ColorSwatches.bestTextColor(on: sport.accent))
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(team?.name ?? "Select Team \(side)")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                    Text(team?.sport.label ?? sport.label)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                replaceWithQuick()
                haptics.light()
            } label: {
                Label("Quick create", systemImage: "bolt.fill")
            }
            if let _ = team {
                Button(role: .destructive) {
                    if side == "A" { teamA = nil } else { teamB = nil }
                    haptics.warning()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Logic

    private var canStart: Bool {
        guard let a = teamA, let b = teamB else { return false }
        return a.id != b.id
    }

    private func startMatch() {
        guard let a = teamA, let b = teamB else {
            errorText = "Выберите обе команды."
            haptics.error()
            return
        }
        guard a.id != b.id else {
            errorText = "Команды не могут совпадать."
            haptics.error()
            return
        }
        let created = matchesRepo.createMatch(sport: sport, teamA: a, teamB: b, rules: rules)
        if created.id != .init(uuidString: "00000000-0000-0000-0000-000000000000")! {
            haptics.success()
            didCreateMatch = true
        } else {
            errorText = "Не удалось создать матч."
            haptics.error()
        }
    }

    private func preloadTeamsIfPossible() {
        let list = teamsRepo.teams(for: sport)
        if list.count >= 2 {
            teamA = list[0]
            teamB = list[1]
        } else if list.count == 1 {
            teamA = list[0]
            teamB = nil
        } else {
            teamA = nil
            teamB = nil
        }
    }

    @discardableResult
    private func autoCreateTeam(name: String) -> Team {
        teamsRepo.createTeam(
            name: name,
            sport: sport,
            badgeName: teamsRepo.suggestBadgeName(),
            colorIndex: teamsRepo.suggestColorIndex(),
            players: []
        )
    }

    private func quickTeamName(b: Bool = false) -> String {
        b ? "Team B" : "Team A"
    }
}

// MARK: - Presets Row

private struct PresetsRow: View {
    @EnvironmentObject private var theme: AppTheme
    let sport: SportKind
    let onSelect: (MatchRules) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Presets")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(theme.palette.textSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    presetButton(title: "Default", rules: MatchRules.default(for: sport), accent: sport.accent)

                    // Generic quick presets
                    switch sport {
                    case .volleyball:
                        presetButton(title: "Bo3 • 25 (+2)", rules: MatchRules(mode: .sets, sport: sport, sets: .init(setsToWin: 2, pointsPerSet: 25, winByTwo: true)), accent: .orange)
                        presetButton(title: "Bo5 • 15 (+2)", rules: MatchRules(mode: .sets, sport: sport, sets: .init(setsToWin: 3, pointsPerSet: 15, winByTwo: true)), accent: .yellow)
                    case .tableTennis:
                        presetButton(title: "Bo5 • 11 (+2)", rules: MatchRules(mode: .sets, sport: sport, sets: .init(setsToWin: 3, pointsPerSet: 11, winByTwo: true)), accent: .cyan)
                    case .tennis:
                        presetButton(title: "Bo3 • 6 (+2)", rules: MatchRules(mode: .sets, sport: sport, sets: .init(setsToWin: 2, pointsPerSet: 6, winByTwo: true)), accent: .green)
                    case .badminton:
                        presetButton(title: "Bo3 • 21 (+2)", rules: MatchRules(mode: .sets, sport: sport, sets: .init(setsToWin: 2, pointsPerSet: 21, winByTwo: true)), accent: .mint)
                    case .football:
                        presetButton(title: "2×45", rules: MatchRules(mode: .timed, sport: sport, time: .init(periods: 2, secondsPerPeriod: 45*60, allowDraw: true)), accent: .green)
                        presetButton(title: "2×20", rules: MatchRules(mode: .timed, sport: sport, time: .init(periods: 2, secondsPerPeriod: 20*60, allowDraw: true)), accent: .teal)
                    case .basketball:
                        presetButton(title: "4×10 +OT", rules: MatchRules(mode: .timed, sport: sport, time: .init(periods: 4, secondsPerPeriod: 10*60, allowDraw: false, overtimeSeconds: 5*60)), accent: .orange)
                        presetButton(title: "4×8 +OT", rules: MatchRules(mode: .timed, sport: sport, time: .init(periods: 4, secondsPerPeriod: 8*60, allowDraw: false, overtimeSeconds: 3*60)), accent: .yellow)
                    case .hockey:
                        presetButton(title: "3×20 +OT", rules: MatchRules(mode: .timed, sport: sport, time: .init(periods: 3, secondsPerPeriod: 20*60, allowDraw: false, overtimeSeconds: 5*60)), accent: .blue)
                    case .esportsCS:
                        presetButton(title: "To 13", rules: MatchRules(mode: .points, sport: sport, points: .init(target: 13, winByTwo: false)), accent: .gray)
                        presetButton(title: "To 16", rules: MatchRules(mode: .points, sport: sport, points: .init(target: 16, winByTwo: false)), accent: .indigo)
                    case .esportsDota, .esportsLOL:
                        presetButton(title: "Bo3", rules: MatchRules(mode: .sets, sport: sport, sets: .init(setsToWin: 2, pointsPerSet: 1, winByTwo: false)), accent: .purple)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func presetButton(title: String, rules: MatchRules, accent: Color) -> some View {
        Button {
            onSelect(rules)
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(ColorSwatches.softVerticalGradient(accent))
                .foregroundColor(ColorSwatches.bestTextColor(on: accent))
                .clipShape(Capsule())
                .shadow(color: ColorSwatches.shadow(for: accent), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Rules Editor

private struct RulesEditor: View {
    @EnvironmentObject private var theme: AppTheme
    @Binding var rules: MatchRules

    var body: some View {
        VStack(spacing: 12) {
            Picker("Mode", selection: Binding(get: { rules.mode }, set: { rules = rules.withMode($0) })) {
                Text("Points").tag(MatchRules.Mode.points)
                Text("Sets").tag(MatchRules.Mode.sets)
                Text("Timed").tag(MatchRules.Mode.timed)
            }
            .pickerStyle(.segmented)

            switch rules.mode {
            case .points:
                pointsEditor
            case .sets:
                setsEditor
            case .timed:
                timeEditor
            }
        }
        .padding(.vertical, 4)
    }

    private var pointsEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Stepper(value: Binding(
                get: { rules.points?.target ?? 21 },
                set: { rules = rules.withPoints(target: max(1, min($0, MatchRules.hardMaxPoints)), winByTwo: rules.points?.winByTwo ?? false) }
            ), in: 1...MatchRules.hardMaxPoints, step: 1) {
                HStack {
                    Text("Target")
                    Spacer()
                    Text("\(rules.points?.target ?? 21)")
                        .foregroundColor(.secondary)
                }
            }
            Toggle("Win by 2", isOn: Binding(
                get: { rules.points?.winByTwo ?? false },
                set: { rules = rules.withPoints(target: rules.points?.target ?? 21, winByTwo: $0) }
            ))
        }
    }

    private var setsEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Stepper(value: Binding(
                get: { rules.sets?.setsToWin ?? 2 },
                set: { rules = rules.withSets(setsToWin: max(1, min($0, MatchRules.hardMaxSets)),
                                              pointsPerSet: rules.sets?.pointsPerSet ?? 25,
                                              winByTwo: rules.sets?.winByTwo ?? true) }
            ), in: 1...MatchRules.hardMaxSets, step: 1) {
                HStack {
                    Text("Sets to win")
                    Spacer()
                    Text("\(rules.sets?.setsToWin ?? 2)")
                        .foregroundColor(.secondary)
                }
            }

            Stepper(value: Binding(
                get: { rules.sets?.pointsPerSet ?? 25 },
                set: { rules = rules.withSets(setsToWin: rules.sets?.setsToWin ?? 2,
                                              pointsPerSet: max(1, min($0, MatchRules.hardMaxPoints)),
                                              winByTwo: rules.sets?.winByTwo ?? true) }
            ), in: 1...MatchRules.hardMaxPoints, step: 1) {
                HStack {
                    Text("Points per set")
                    Spacer()
                    Text("\(rules.sets?.pointsPerSet ?? 25)")
                        .foregroundColor(.secondary)
                }
            }

            Toggle("Win by 2", isOn: Binding(
                get: { rules.sets?.winByTwo ?? true },
                set: { rules = rules.withSets(setsToWin: rules.sets?.setsToWin ?? 2,
                                              pointsPerSet: rules.sets?.pointsPerSet ?? 25,
                                              winByTwo: $0) }
            ))
        }
    }

    private var timeEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Stepper(value: Binding(
                get: { rules.time?.periods ?? 2 },
                set: { rules = rules.withTime(periods: max(1, min($0, 12)),
                                              secondsPerPeriod: rules.time?.secondsPerPeriod ?? 600,
                                              allowDraw: rules.time?.allowDraw ?? true,
                                              overtimeSeconds: rules.time?.overtimeSeconds,
                                              stopOnScore: rules.time?.stopOnScore ?? false) }
            ), in: 1...12, step: 1) {
                HStack {
                    Text("Periods")
                    Spacer()
                    Text("\(rules.time?.periods ?? 2)")
                        .foregroundColor(.secondary)
                }
            }

            Stepper(value: Binding(
                get: { (rules.time?.secondsPerPeriod ?? 600) / 60 },
                set: { rules = rules.withTime(periods: rules.time?.periods ?? 2,
                                              secondsPerPeriod: max(30, min($0*60, MatchRules.hardMaxPeriodSeconds)),
                                              allowDraw: rules.time?.allowDraw ?? true,
                                              overtimeSeconds: rules.time?.overtimeSeconds,
                                              stopOnScore: rules.time?.stopOnScore ?? false) }
            ), in: 1...120, step: 1) {
                HStack {
                    Text("Minutes per period")
                    Spacer()
                    Text("\((rules.time?.secondsPerPeriod ?? 600) / 60)m")
                        .foregroundColor(.secondary)
                }
            }

            Toggle("Allow draw", isOn: Binding(
                get: { rules.time?.allowDraw ?? true },
                set: {
                    let allow = $0
                    rules = rules.withTime(periods: rules.time?.periods ?? 2,
                                           secondsPerPeriod: rules.time?.secondsPerPeriod ?? 600,
                                           allowDraw: allow,
                                           overtimeSeconds: allow ? nil : (rules.time?.overtimeSeconds ?? 300),
                                           stopOnScore: rules.time?.stopOnScore ?? false)
                }
            ))

            if rules.time?.allowDraw == false {
                Stepper(value: Binding(
                    get: { (rules.time?.overtimeSeconds ?? 300) / 60 },
                    set: {
                        rules = rules.withTime(periods: rules.time?.periods ?? 2,
                                               secondsPerPeriod: rules.time?.secondsPerPeriod ?? 600,
                                               allowDraw: false,
                                               overtimeSeconds: max(1, min($0, 60)) * 60,
                                               stopOnScore: rules.time?.stopOnScore ?? false)
                    }
                ), in: 1...60, step: 1) {
                    HStack {
                        Text("Overtime (minutes)")
                        Spacer()
                        Text("\((rules.time?.overtimeSeconds ?? 300) / 60)m")
                            .foregroundColor(.secondary)
                    }
                }
            }

            Toggle("Stop timer on score", isOn: Binding(
                get: { rules.time?.stopOnScore ?? false },
                set: { rules = rules.withTime(periods: rules.time?.periods ?? 2,
                                              secondsPerPeriod: rules.time?.secondsPerPeriod ?? 600,
                                              allowDraw: rules.time?.allowDraw ?? true,
                                              overtimeSeconds: rules.time?.overtimeSeconds,
                                              stopOnScore: $0) }
            ))
        }
    }
}

// MARK: - Team Picker Sheet

private struct TeamPickerSheet: View {
    @EnvironmentObject private var theme: AppTheme
    @EnvironmentObject private var teamsRepo: TeamsRepository
    @Environment(\.dismiss) private var dismiss

    let title: String
    let sport: SportKind
    let selected: UUID?
    let createQuick: () -> String
    let onPick: (Team) -> Void

    @State private var search: String = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        let name = createQuick()
                        let t = teamsRepo.createTeam(
                            name: name,
                            sport: sport,
                            badgeName: teamsRepo.suggestBadgeName(),
                            colorIndex: teamsRepo.suggestColorIndex(),
                            players: []
                        )
                        onPick(t)
                        dismiss()
                    } label: {
                        Label("Quick create team", systemImage: "bolt.fill")
                            .foregroundStyle(sport.accent)
                    }
                }

                Section("Teams for \(sport.label)") {
                    ForEach(source(), id: \.id) { t in
                        Button {
                            onPick(t)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(ColorSwatches.ringGradient(t.color))
                                        .frame(width: 32, height: 32)
                                    t.badge
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 14, height: 14)
                                        .foregroundStyle(t.foregroundOnColor)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(t.name)
                                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    if t.playerCount > 0 {
                                        Text("\(t.playerCount) players")
                                            .font(.system(size: 11, weight: .regular, design: .rounded))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if selected == t.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(theme.background)
            .navigationTitle(Text(title))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search teams")
        }
        .tint(theme.accent)
    }

    private func source() -> [Team] {
        let all = teamsRepo.teams(for: sport)
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return all }
        return all.filter { $0.matches(q) }
    }
}

// MARK: - Small bits

private struct SportChip: View {
    @EnvironmentObject private var theme: AppTheme
    let kind: SportKind
    let selected: Bool

    var body: some View {
        HStack(spacing: 8) {
            kind.icon.imageScale(.small)
            Text(kind.shortLabel)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .foregroundColor(ColorSwatches.bestTextColor(on: background))
        .background(ColorSwatches.softVerticalGradient(background))
        .overlay(
            Capsule().strokeBorder(.white.opacity(selected ? 0.28 : 0.10), lineWidth: selected ? 1.2 : 0.8)
        )
        .clipShape(Capsule())
        .shadow(color: ColorSwatches.shadow(for: background), radius: selected ? 8 : 4, x: 0, y: selected ? 4 : 2)
        .scaleEffect(selected ? 1.05 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.9), value: selected)
    }

    private var background: Color {
        selected ? kind.accent : theme.palette.secondary
    }
}
