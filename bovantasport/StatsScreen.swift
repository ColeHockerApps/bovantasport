//
//  StatsScreen.swift
//  Bovanta:Sport
//
//  Created on 2025-10-14
//

import SwiftUI
import Combine

/// Экран статистики: сводка по видам спорта и таблица команд с винрейтом/сериями.
/// Источник данных — `StatsService` (автоматически слушает сторадж).
public struct StatsScreen: View {
    // MARK: - Env
    @EnvironmentObject private var theme: AppTheme
    @EnvironmentObject private var haptics: HapticsManager
    @EnvironmentObject private var stats: StatsService

    // MARK: - State (UI)
    @State private var filterSport: SportKind? = nil
    @State private var search: String = ""
    @State private var minGames: Int = 1
    @State private var sortMode: SortMode = .winRate

    public init() {}

    // MARK: - Body
    public var body: some View {
        VStack(spacing: 0) {
            headerBar

            ScrollView {
                VStack(spacing: 16) {
                    overviewSection
                    controlsSection
                    topBlocksSection
                    recordsSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(theme.background.ignoresSafeArea())
        }
        .navigationTitle("Statistics")
        .background(theme.background.ignoresSafeArea())
    }

    // MARK: - Header
    private var headerBar: some View {
        HStack(spacing: 10) {
            Text("Stats")
                .font(theme.typography.titleMedium)
                .foregroundColor(theme.palette.textPrimary)

            Spacer()

            Button {
                stats.refreshFromStorage()
                haptics.soft()
            } label: {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .imageScale(.large)
                    .foregroundStyle(theme.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(theme.background)
    }

    // MARK: - Overview
    private var overviewSection: some View {
        let overviews = stats.summary.sportOverviews
        return VStack(alignment: .leading, spacing: 10) {
            Text("Overview")
                .font(theme.typography.titleSmall)
                .foregroundColor(theme.palette.textSecondary)

            if overviews.isEmpty {
                EmptyStateView(
                    title: "No statistics yet",
                    subtitle: "Play a few matches — summaries will appear here.",
                    icon: "chart.bar.doc.horizontal.fill"
                )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(overviews, id: \.id) { ov in
                            OverviewCard(overview: ov)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: - Controls
    private var controlsSection: some View {
        VStack(spacing: 10) {
            // Sport filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterChip(
                        title: "All",
                        icon: Image(systemName: "circle.grid.2x2.fill"),
                        selected: filterSport == nil,
                        color: theme.palette.secondary
                    ) {
                        filterSport = nil
                        haptics.select()
                    }

                    ForEach(SportKind.allCases, id: \.self) { kind in
                        FilterChip(
                            title: kind.shortLabel,
                            icon: kind.icon,
                            selected: filterSport == kind,
                            color: kind.accent
                        ) {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                                filterSport = kind
                            }
                            haptics.select()
                        }
                    }
                }
            }

            // Search + sort + min games
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search teams", text: $search)
                        .textInputAutocapitalization(.words)
                        .disableAutocorrection(true)
                        .onChange(of: search) { _ in haptics.soft() }
                    if !search.isEmpty {
                        Button {
                            search = ""
                            haptics.select()
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(theme.palette.surface.cornerRadius(12))

                HStack(spacing: 10) {
                    Picker("Sort", selection: $sortMode) {
                        ForEach(SortMode.allCases, id: \.self) { m in
                            Text(m.title).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)

                    Stepper("Min \(minGames) games", value: $minGames, in: 1...100)
                        .onChange(of: minGames) { _ in haptics.soft() }
                }
            }
        }
    }

    // MARK: - Top blocks
    private var topBlocksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Highlights")
                .font(theme.typography.titleSmall)
                .foregroundColor(theme.palette.textSecondary)

            let ov = filterSport.flatMap { stats.overview(for: $0) }
            let matchesCount = ov?.matches ?? stats.summary.sportOverviews.reduce(0) { $0 + $1.matches }
            let finishedCount = ov?.finished ?? stats.summary.sportOverviews.reduce(0) { $0 + $1.finished }
            let drawsCount = ov?.draws ?? stats.summary.sportOverviews.reduce(0) { $0 + $1.draws }
            let avgTotal = ov?.avgTotalPoints ?? {
                let totalMatches = Double(max(1, stats.summary.sportOverviews.reduce(0) { $0 + $1.matches }))
                let totalPoints = stats.summary.sportOverviews.reduce(0.0) { $0 + (Double($1.matches) * $1.avgTotalPoints) }
                return totalPoints / totalMatches
            }()

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                StatCard(title: "Matches", value: "\(matchesCount)", subtitle: "total", accent: theme.accent)
                StatCard(title: "Finished", value: "\(finishedCount)", subtitle: "completed", accent: .green)
                StatCard(title: "Draws", value: "\(drawsCount)", subtitle: "timed sports", accent: .blue)
                StatCard(title: "Avg total", value: String(format: "%.1f", avgTotal), subtitle: "points/sets/goals", accent: .orange)
            }
        }
    }

    // MARK: - Records
    private var recordsSection: some View {
        let all = stats.summary.teamRecords
        let filteredBySport = filterSport == nil ? all : all.filter { $0.sport == filterSport! }
        let filteredByGames = filteredBySport.filter { $0.games >= minGames }
        let filteredByQuery: [StatsSummary.TeamRecord] = {
            let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !q.isEmpty else { return filteredByGames }
            return filteredByGames.filter { $0.teamName.lowercased().contains(q) }
        }()

        let sorted = sort(filteredByQuery)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Teams")
                    .font(theme.typography.titleSmall)
                    .foregroundColor(theme.palette.textSecondary)
                Spacer()
                Text("\(sorted.count) result\(sorted.count == 1 ? "" : "s")")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundColor(theme.palette.textSecondary)
            }

            if sorted.isEmpty {
                EmptyStateView(
                    title: "No records",
                    subtitle: "Try lowering the Min games filter or reset search.",
                    icon: "line.3.horizontal.decrease.circle"
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(sorted, id: \.id) { rec in
                        RecordRow(record: rec)
                    }
                }
            }
        }
    }

    // MARK: - Sort
    private enum SortMode: String, CaseIterable {
        case winRate, games, streak, avgMargin

        var title: String {
            switch self {
            case .winRate: return "Win %"
            case .games:   return "Games"
            case .streak:  return "Streak"
            case .avgMargin: return "Avg ±"
            }
        }
    }

    private func sort(_ input: [StatsSummary.TeamRecord]) -> [StatsSummary.TeamRecord] {
        switch sortMode {
        case .winRate:
            return input.sorted {
                if $0.winRate != $1.winRate { return $0.winRate > $1.winRate }
                if $0.games != $1.games { return $0.games > $1.games }
                return $0.teamName.localizedCaseInsensitiveCompare($1.teamName) == .orderedAscending
            }
        case .games:
            return input.sorted {
                if $0.games != $1.games { return $0.games > $1.games }
                return $0.teamName.localizedCaseInsensitiveCompare($1.teamName) == .orderedAscending
            }
        case .streak:
            return input.sorted {
                if $0.currentStreak != $1.currentStreak { return $0.currentStreak > $1.currentStreak }
                if $0.games != $1.games { return $0.games > $1.games }
                return $0.teamName.localizedCaseInsensitiveCompare($1.teamName) == .orderedAscending
            }
        case .avgMargin:
            return input.sorted {
                if $0.avgMargin != $1.avgMargin { return $0.avgMargin > $1.avgMargin }
                if $0.games != $1.games { return $0.games > $1.games }
                return $0.teamName.localizedCaseInsensitiveCompare($1.teamName) == .orderedAscending
            }
        }
    }
}

// MARK: - Cards & Rows

private struct OverviewCard: View {
    @EnvironmentObject private var theme: AppTheme
    let overview: StatsSummary.SportOverview

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                overview.sport.icon.imageScale(.medium)
                Text(overview.sport.label)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(overview.sport.accent)

            HStack(spacing: 12) {
                metric("Matches", "\(overview.matches)")
                metric("Finished", "\(overview.finished)")
                metric("Draws", "\(overview.draws)")
            }

            Divider().opacity(0.2)

            HStack(spacing: 12) {
                metric("Avg total", String(format: "%.1f", overview.avgTotalPoints))
                let shareTimed = Int(round((overview.modeShare[.timed] ?? 0) * 100))
                metric("Timed", "\(shareTimed)%")
            }
        }
        .padding(12)
        .frame(maxWidth: 280, alignment: .leading)
        .background(ColorSwatches.softVerticalGradient(overview.sport.accent))
        .foregroundColor(ColorSwatches.bestTextColor(on: overview.sport.accent))
        .cornerRadius(12)
        .shadow(color: ColorSwatches.shadow(for: overview.sport.accent), radius: 6, x: 0, y: 3)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .opacity(0.9)
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
        }
    }
}

private struct RecordRow: View {
    @EnvironmentObject private var theme: AppTheme
    let record: StatsSummary.TeamRecord

    var body: some View {
        HStack(spacing: 12) {
            // Sport chip
            Chip(text: record.sport.shortLabel, icon: record.sport.icon, color: record.sport.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(record.teamName)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(theme.palette.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text("\(record.wins)-\(record.losses)\(record.draws > 0 ? "-\(record.draws)" : "")")
                    Text("• \(percent(record.winRate)) win")
                    Text("• \(record.games) games")
                }
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundColor(theme.palette.textSecondary)
                .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(streakText(record.currentStreak))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(streakColor(record.currentStreak))
                Text(String(format: "±%.1f", record.avgMargin))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(record.avgMargin >= 0 ? .green : .red)
            }
        }
        .padding(12)
        .background(theme.palette.surface.cornerRadius(12))
    }

    private func percent(_ v: Double) -> String {
        "\(Int(round(v * 100)))%"
    }

    private func streakText(_ s: Int) -> String {
        if s > 0 { return "W\(s) streak" }
        if s < 0 { return "L\(-s) streak" }
        return "No streak"
    }

    private func streakColor(_ s: Int) -> Color {
        if s > 0 { return .green }
        if s < 0 { return .red }
        return theme.palette.textSecondary
    }
}

// MARK: - UI Bits reused (local copies to avoid cross-file deps here)

private struct FilterChip: View {
    @EnvironmentObject private var theme: AppTheme
    let title: String
    let icon: Image
    let selected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                icon.imageScale(.small)
                Text(title).font(.system(size: 13, weight: .semibold, design: .rounded))
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
        .buttonStyle(.plain)
    }

    private var background: Color {
        selected ? color : theme.palette.secondary
    }
}


private struct Chip: View {
    let text: String
    let icon: Image
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            icon.imageScale(.small)
            Text(text).font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(ColorSwatches.softVerticalGradient(color))
        .foregroundColor(ColorSwatches.bestTextColor(on: color))
        .clipShape(Capsule())
    }
}
