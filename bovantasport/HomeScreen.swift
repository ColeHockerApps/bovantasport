//
//  HomeScreen.swift
//  Bovanta:Sport
//
//  Created on 2025-10-14
//

import SwiftUI
import Combine

/// Домашний экран: быстрый старт матча, выбор спорта, последние матчи и мини-статистика.
/// Без заглушек: быстрый матч реально создаётся и попадает в историю.
public struct HomeScreen: View {
    // MARK: - Env
    @EnvironmentObject private var theme: AppTheme
    @EnvironmentObject private var haptics: HapticsManager
    @EnvironmentObject private var teamsRepo: TeamsRepository
    @EnvironmentObject private var matchesRepo: MatchesRepository
    @EnvironmentObject private var stats: StatsService

    // MARK: - State
    @AppStorage("home.lastSportKey") private var lastSportKey: String = SportKind.football.key
    @State private var selectedSport: SportKind = .football
    @State private var presentingQuickMatchSheet: Bool = false
    @State private var createdMatch: Match? = nil
    @State private var searchText: String = ""

    // MARK: - Init
    public init() {}

    // MARK: - Body
    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                sportPickerSection

                quickStartSection

                statsDigestSection

                recentSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(theme.background.ignoresSafeArea())
        .onAppear {
            selectedSport = SportKind.fromKey(lastSportKey)
        }
        .sheet(isPresented: $presentingQuickMatchSheet) {
            QuickMatchSheet(selectedSport: $selectedSport) { a, b, rules in
                let m = matchesRepo.createMatch(sport: selectedSport, teamA: a, teamB: b, rules: rules)
                createdMatch = m
                haptics.success()
            }
            .environmentObject(theme)
            .environmentObject(teamsRepo)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search matches/teams")
        .onChange(of: searchText) { _ in
            haptics.soft()
        }
    }

    // MARK: - Sections

    private var sportPickerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose Sport")
                .font(theme.typography.titleSmall)
                .foregroundColor(theme.palette.textSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(SportKind.allCases, id: \.self) { kind in
                        SportChip(kind: kind, isSelected: kind == selectedSport)
                            .onTapGesture {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.9, blendDuration: 0.2)) {
                                    selectedSport = kind
                                    lastSportKey = kind.key
                                }
                                haptics.select()
                            }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var quickStartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Quick Start")
                    .font(theme.typography.titleMedium)
                    .foregroundColor(theme.palette.textPrimary)
                Spacer()
                Button {
                    presentingQuickMatchSheet = true
                    haptics.light()
                } label: {
                    Label("New Match", systemImage: "play.fill")
                        .font(theme.typography.label)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(ColorSwatches.softVerticalGradient(selectedSport.accent))
                        .foregroundColor(ColorSwatches.bestTextColor(on: selectedSport.accent))
                        .clipShape(Capsule())
                        .shadow(color: ColorSwatches.shadow(for: selectedSport.accent), radius: 6, x: 0, y: 3)
                }
                .buttonStyle(.plain)
            }

            // Small helper row: quickly create A/B and start with defaults
            Button {
                quickStartAuto()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "bolt.fill")
                        .imageScale(.medium)
                    Text("Auto-pair two teams for \(selectedSport.label)")
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .opacity(0.6)
                }
                .font(theme.typography.body)
                .foregroundColor(theme.palette.textPrimary)
                .padding(12)
                .background(theme.palette.surface.cornerRadius(12))
            }
            .buttonStyle(.plain)
        }
    }

    private var statsDigestSection: some View {
        let digest = stats.sportDigest()
        return VStack(alignment: .leading, spacing: 10) {
            Text("Overview")
                .font(theme.typography.titleSmall)
                .foregroundColor(theme.palette.textSecondary)

            if digest.isEmpty {
                EmptyStateView(
                    title: "No statistics yet",
                    subtitle: "Play a few matches to see trends here.",
                    icon: "chart.bar.doc.horizontal.fill"
                )
                .padding(.vertical, 8)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(digest, id: \.sport) { item in
                        StatCard(
                            title: item.sport.shortLabel,
                            value: "\(item.matches)",
                            subtitle: "matches",
                            accent: item.sport.accent
                        )
                    }
                }
            }
        }
    }

    private var recentSection: some View {
        let source = searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? matchesRepo.recent(limit: 20)
            : matchesRepo.search(searchText)

        return VStack(alignment: .leading, spacing: 10) {
            Text("Recent Matches")
                .font(theme.typography.titleSmall)
                .foregroundColor(theme.palette.textSecondary)

            if source.isEmpty {
                EmptyStateView(
                    title: "No matches yet",
                    subtitle: "Start your first match to build history.",
                    icon: "sportscourt.fill"
                )
                .padding(.vertical, 8)
            } else {
                VStack(spacing: 8) {
                    ForEach(source, id: \.id) { match in
                        NavigationLink {
                            MatchReadOnlyView(match: match)
                                .navigationTitle("Match")
                        } label: {
                            RecentMatchRow(match: match)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - Actions

    private func quickStartAuto() {

        var teams = teamsRepo.teams(for: selectedSport)
        if teams.count < 2 {
            // auto-create minimal teams with suggested colors/badges
            let tA = teamsRepo.createTeam(
                name: "Team A",
                sport: selectedSport,
                badgeName: teamsRepo.suggestBadgeName(),
                colorIndex: teamsRepo.suggestColorIndex(),
                players: []
            )
            let tB = teamsRepo.createTeam(
                name: "Team B",
                sport: selectedSport,
                badgeName: teamsRepo.suggestBadgeName(),
                colorIndex: teamsRepo.suggestColorIndex(),
                players: []
            )
            teams = [tA, tB]
        } else {
            teams = Array(teams.prefix(2))
        }

        let rules = MatchRules.default(for: selectedSport)
        let m = matchesRepo.createMatch(sport: selectedSport, teamA: teams[0], teamB: teams[1], rules: rules)
        createdMatch = m
        haptics.success()
    }
}

// MARK: - Subviews

private struct SportChip: View {
    @EnvironmentObject private var theme: AppTheme
    let kind: SportKind
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            kind.icon
                .imageScale(.medium)
            Text(kind.shortLabel)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .foregroundColor(ColorSwatches.bestTextColor(on: background))
        .background(ColorSwatches.softVerticalGradient(background))
        .overlay(
            Capsule()
                .strokeBorder(.white.opacity(isSelected ? 0.25 : 0.08), lineWidth: isSelected ? 1.2 : 0.8)
        )
        .clipShape(Capsule())
        .shadow(color: ColorSwatches.shadow(for: background), radius: isSelected ? 8 : 4, x: 0, y: isSelected ? 4 : 2)
        .scaleEffect(isSelected ? 1.04 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.9, blendDuration: 0.2), value: isSelected)
    }

    private var background: Color {
        isSelected ? kind.accent : theme.palette.secondary
    }
}

private struct RecentMatchRow: View {
    @EnvironmentObject private var theme: AppTheme
    let match: Match

    var body: some View {
        HStack(spacing: 12) {
            // Team A badge
            ZStack {
                Circle()
                    .fill(ColorSwatches.ringGradient(match.teamA.color))
                    .frame(width: 36, height: 36)
                match.teamA.badge
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .foregroundStyle(match.teamA.foregroundOnColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("\(match.teamA.name)  vs  \(match.teamB.name)")
                        .font(theme.typography.body)
                        .foregroundColor(theme.palette.textPrimary)
                        .lineLimit(1)
                    Spacer()
                }
                HStack(spacing: 8) {
                    Label(match.sport.shortLabel, systemImage: "sportscourt")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(match.sport.accent)
                    Text(match.progressDescription)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(theme.palette.textSecondary)
                        .lineLimit(1)
                    Spacer()
                    Text(match.createdAt, style: .date)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(theme.palette.textSecondary.opacity(0.8))
                }
            }

            // Team B badge
            ZStack {
                Circle()
                    .fill(ColorSwatches.ringGradient(match.teamB.color))
                    .frame(width: 36, height: 36)
                match.teamB.badge
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .foregroundStyle(match.teamB.foregroundOnColor)
            }
        }
        .padding(12)
        .background(theme.palette.surface.cornerRadius(14))
    }
}

private struct MatchReadOnlyView: View {
    @EnvironmentObject private var theme: AppTheme
    let match: Match

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                TeamBadge(title: match.teamA.name, color: match.teamA.color, icon: match.teamA.badge, textColor: match.teamA.foregroundOnColor)
                Text("vs")
                    .font(theme.typography.titleMedium)
                    .foregroundColor(theme.palette.textSecondary)
                TeamBadge(title: match.teamB.name, color: match.teamB.color, icon: match.teamB.badge, textColor: match.teamB.foregroundOnColor)
                Spacer()
            }

            HStack {
                match.sport.icon
                Text(match.sport.label)
                    .font(theme.typography.titleSmall)
                Spacer()
            }
            .foregroundStyle(match.sport.accent)

            VStack(alignment: .leading, spacing: 8) {
                Text("Status")
                    .font(theme.typography.titleSmall)
                    .foregroundColor(theme.palette.textSecondary)
                Text(match.progressDescription)
                    .font(theme.typography.titleMedium)
                    .foregroundColor(theme.palette.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(theme.palette.surface.cornerRadius(12))

            List {
                Section("Event Log") {
                    if match.events.isEmpty {
                        Text("No events recorded.")
                            .foregroundColor(theme.palette.textSecondary)
                    } else {
                        ForEach(match.events) { e in
                            HStack {
                                Text(e.at, style: .time)
                                    .foregroundColor(theme.palette.textSecondary)
                                Text(render(event: e))
                                Spacer()
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
        .padding(16)
        .background(theme.background.ignoresSafeArea())
    }

    private func render(event: Match.Event) -> String {
        switch event.kind {
        case .score:
            return "Score +\(event.value ?? 1) for \(event.side == .a ? match.teamA.name : match.teamB.name)"
        case .unscore:
            return "Score \(event.value ?? -1) for \(event.side == .a ? match.teamA.name : match.teamB.name)"
        case .setWin:
            return "Set won by \(event.side == .a ? match.teamA.name : match.teamB.name)"
        case .periodEnd:
            return "Period ended"
        case .periodStart:
            return "Period started"
        case .matchEnd:
            return "Match finished — winner: \(event.side == .a ? match.teamA.name : match.teamB.name)"
        case .note:
            return event.text ?? "Note"
        }
    }
}

private struct TeamBadge: View {
    let title: String
    let color: Color
    let icon: Image
    let textColor: Color

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(ColorSwatches.ringGradient(color))
                    .frame(width: 34, height: 34)
                icon
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .foregroundStyle(textColor)
            }
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
        }
    }
}

// MARK: - Quick Match Sheet

private struct QuickMatchSheet: View {
    @EnvironmentObject private var theme: AppTheme
    @EnvironmentObject private var teamsRepo: TeamsRepository
    @Environment(\.dismiss) private var dismiss

    @Binding var selectedSport: SportKind

    @State private var teamA: Team?
    @State private var teamB: Team?
    @State private var rules: MatchRules = MatchRules.default(for: .football)

    let onCreate: (_ teamA: Team, _ teamB: Team, _ rules: MatchRules) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Capsule()
                .fill(.secondary.opacity(0.3))
                .frame(width: 44, height: 5)
                .padding(.top, 8)

            HStack {
                Text("New Match")
                    .font(theme.typography.titleMedium)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .imageScale(.large)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Sport
            VStack(alignment: .leading, spacing: 8) {
                Text("Sport")
                    .font(theme.typography.label)
                    .foregroundColor(theme.palette.textSecondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(SportKind.allCases, id: \.self) { kind in
                            SportChip(kind: kind, isSelected: kind == selectedSport)
                                .onTapGesture {
                                    withAnimation(.spring) {
                                        selectedSport = kind
                                        rules = MatchRules.default(for: kind)
                                        // Auto-suggest teams for this sport
                                        suggestTeams()
                                    }
                                }
                        }
                    }
                }
            }

            // Teams pick
            VStack(alignment: .leading, spacing: 8) {
                Text("Teams")
                    .font(theme.typography.label)
                    .foregroundColor(theme.palette.textSecondary)

                HStack(spacing: 12) {
                    teamPickerButton(title: teamA?.name ?? "Select Team A", team: teamA, sideLabel: "A") {
                        teamA = pickNext(for: selectedSport, excluding: teamB?.id)
                    }
                    teamPickerButton(title: teamB?.name ?? "Select Team B", team: teamB, sideLabel: "B") {
                        teamB = pickNext(for: selectedSport, excluding: teamA?.id)
                    }
                }
            }

            // Rules (compact)
            VStack(alignment: .leading, spacing: 8) {
                Text("Rules")
                    .font(theme.typography.label)
                    .foregroundColor(theme.palette.textSecondary)

                RuleSummaryView(rules: rules)
                    .onTapGesture {
                        // Quick cycle presets for convenience
                        cycleRules()
                    }
            }

            Button {
                let a = teamA ?? autoCreate(name: "Team A")
                let b = teamB ?? autoCreate(name: "Team B", avoid: a.id)
                onCreate(a, b, rules)
                dismiss()
            } label: {
                Text("Start Match")
                    .font(theme.typography.titleSmall)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(ColorSwatches.softVerticalGradient(selectedSport.accent))
                    .foregroundColor(ColorSwatches.bestTextColor(on: selectedSport.accent))
                    .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .padding(.top, 6)

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(theme.background.ignoresSafeArea())
        .onAppear {
            rules = MatchRules.default(for: selectedSport)
            suggestTeams()
        }
    }

    private func teamPickerButton(title: String, team: Team?, sideLabel: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(ColorSwatches.ringGradient(team?.color ?? selectedSport.accent))
                        .frame(width: 34, height: 34)
                    Text(sideLabel)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(ColorSwatches.bestTextColor(on: team?.color ?? selectedSport.accent))
                        .opacity(team == nil ? 0.85 : 0.0)
                    if let t = team {
                        t.badge
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                            .foregroundStyle(t.foregroundOnColor)
                    }
                }
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Spacer()
                Image(systemName: "arrow.2.circlepath")
                    .imageScale(.medium)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(AppTheme().palette.surface.cornerRadius(12).opacity(0.001)) // layout-only
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func suggestTeams() {
        let list = teamsRepo.teams(for: selectedSport)
        if list.count >= 2 {
            teamA = list[0]
            teamB = list[1]
        } else {
            teamA = list.first
            teamB = nil
        }
    }

    private func pickNext(for sport: SportKind, excluding: UUID?) -> Team {
        let list = teamsRepo.teams(for: sport).filter { $0.id != excluding }
        if let first = list.first { return first }
        return autoCreate(name: excluding == nil ? "Team A" : "Team B", avoid: excluding)
    }

    @discardableResult
    private func autoCreate(name: String, avoid: UUID? = nil) -> Team {
        var idx = teamsRepo.suggestColorIndex()
        if let avoid = avoid, let avoidTeam = teamsRepo.team(by: avoid) {
            let used: Set<Int> = [avoidTeam.normalizedColorIndex]
            idx = ColorSwatches.nextTeamColorIndex(start: idx, used: used)
        }
        return teamsRepo.createTeam(name: name,
                                    sport: selectedSport,
                                    badgeName: teamsRepo.suggestBadgeName(),
                                    colorIndex: idx,
                                    players: [])
    }

    private func cycleRules() {
        switch rules.mode {
        case .points:
            rules = rules.withSets(setsToWin: 2, pointsPerSet: 15, winByTwo: true)
        case .sets:
            rules = rules.withTime(periods: 2, secondsPerPeriod: 12 * 60, allowDraw: true)
        case .timed:
            rules = rules.withPoints(target: 21, winByTwo: true)
        }
    }
}

private struct RuleSummaryView: View {
    @EnvironmentObject private var theme: AppTheme
    let rules: MatchRules

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .imageScale(.medium)
            Text(rules.shortDescription)
                .font(theme.typography.body)
            Spacer()
            Text("Change")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(theme.accent)
        }
        .padding(12)
        .background(theme.palette.surface.cornerRadius(12))
    }

    private var iconName: String {
        switch rules.mode {
        case .points: return "number.circle.fill"
        case .sets:   return "square.grid.2x2.fill"
        case .timed:  return "timer"
        }
    }
}


