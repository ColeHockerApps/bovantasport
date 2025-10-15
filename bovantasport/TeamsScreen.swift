//
//  TeamsScreen.swift
//  Bovanta:Sport
//
//  Created on 2025-10-14
//

import SwiftUI
import Combine

/// Экран команд: список, поиск, фильтр по виду спорта, создание/редактирование без заглушек.
/// Использует локальный редактор (лист) для создания/правки команды.
public struct TeamsScreen: View {
    // MARK: - Env
    @EnvironmentObject private var theme: AppTheme
    @EnvironmentObject private var haptics: HapticsManager
    @EnvironmentObject private var teamsRepo: TeamsRepository

    // MARK: - State
    @State private var search: String = ""
    @State private var filterSport: SportKind? = nil
    @State private var showingEditor: Bool = false
    @State private var editingTeam: Team? = nil

    public init() {}

    // MARK: - Body
    public var body: some View {
        VStack(spacing: 0) {
            headerBar
            filterBar

            contentList
        }
        .background(theme.background.ignoresSafeArea())
        .sheet(isPresented: $showingEditor) {
            TeamFormSheet(
                teamToEdit: editingTeam,
                initialSport: filterSport
            ) { result in
                switch result {
                case .created(let team):
                    _ = teamsRepo.add(team)
                    haptics.success()
                case .updated(let team):
                    teamsRepo.update(team)
                    haptics.success()
                case .deleted(let id):
                    teamsRepo.delete(teamID: id)
                    haptics.warning()
                case .cancelled:
                    haptics.soft()
                }
            }
            .environmentObject(theme)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Sections

    private var headerBar: some View {
        HStack(spacing: 10) {
            Text("Teams")
                .font(theme.typography.titleMedium)
                .foregroundColor(theme.palette.textPrimary)

            Spacer()

            Button {
                editingTeam = nil
                showingEditor = true
                haptics.light()
            } label: {
                Label("Add Team", systemImage: "plus.circle.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(theme.accent)
                    .font(.title3)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var filterBar: some View {
        VStack(spacing: 8) {
            // Search
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search teams or players", text: $search)
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
            .padding(.horizontal, 16)

            // Sport chips
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
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        }
        .padding(.bottom, 8)
    }

    private var contentList: some View {
        // Source
        let base: [Team] = {
            if let s = filterSport { return teamsRepo.teams(for: s) }
            return teamsRepo.teams.sortedByName()
        }()

        let items: [Team] = {
            let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
            return q.isEmpty ? base : base.filter { $0.matches(q) }
        }()

        return Group {
            if items.isEmpty {
                ScrollView {
                    VStack(spacing: 16) {
                        EmptyStateView(
                            title: "No teams",
                            subtitle: "Create your first team to start playing.",
                            icon: "person.2.fill"
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, 24)

                        Button {
                            editingTeam = nil
                            showingEditor = true
                            haptics.light()
                        } label: {
                            Label("Create Team", systemImage: "plus")
                                .font(theme.typography.titleSmall)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(ColorSwatches.softVerticalGradient(theme.accent))
                                .foregroundColor(ColorSwatches.bestTextColor(on: theme.accent))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity)
                }
                .background(theme.background)
            } else {
                List {
                    ForEach(items, id: \.id) { team in
                        TeamRow(team: team) {
                            // edit tap
                            editingTeam = team
                            showingEditor = true
                            haptics.light()
                        }
                        .listRowBackground(theme.palette.surface)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                teamsRepo.delete(teamID: team.id)
                                haptics.error()
                            } label: {
                                Label("Delete", systemImage: "trash.fill")
                            }
                            Button {
                                editingTeam = team
                                showingEditor = true
                                haptics.light()
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(theme.background)
            }
        }
    }
}

// MARK: - Row

private struct TeamRow: View {
    @EnvironmentObject private var theme: AppTheme
    let team: Team
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Badge
            ZStack {
                Circle()
                    .fill(ColorSwatches.ringGradient(team.color))
                    .frame(width: 40, height: 40)
                team.badge
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .foregroundStyle(team.foregroundOnColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(team.name)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(theme.palette.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Chip(text: team.sport.shortLabel, icon: team.sport.icon, color: team.sport.accent)
                    if team.playerCount > 0 {
                        Label("\(team.playerCount)", systemImage: "person.fill")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(theme.palette.textSecondary)
                    }
                }
            }

            Spacer()

            Button(action: onEdit) {
                Image(systemName: "ellipsis.circle")
                    .imageScale(.large)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

// MARK: - Editor Sheet

private struct TeamFormSheet: View {
    @EnvironmentObject private var theme: AppTheme
    @Environment(\.dismiss) private var dismiss

    enum Result {
        case created(Team)
        case updated(Team)
        case deleted(UUID)
        case cancelled
    }

    let teamToEdit: Team?
    let initialSport: SportKind?
    let onFinish: (Result) -> Void

    @State private var name: String = ""
    @State private var sport: SportKind = .football
    @State private var badgeName: String = "sf:shield.fill"
    @State private var colorIndex: Int = 0
    @State private var players: [Player] = []

    // Player editor
    @State private var newPlayerName: String = ""
    @State private var newPlayerNick: String = ""

    var isEditing: Bool { teamToEdit != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    TextField("Team name", text: $name)
                        .textInputAutocapitalization(.words)
                    Picker("Sport", selection: $sport) {
                        ForEach(SportKind.allCases, id: \.self) { kind in
                            HStack {
                                kind.icon
                                Text(kind.label)
                            }.tag(kind)
                        }
                    }
                }
                .listRowBackground(theme.palette.surface)

                Section("Appearance") {
                    // Badge picker
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(IconLibrary.teamBadgePickerItems(), id: \.name) { item in
                                let selected = badgeName == item.name
                                Button {
                                    badgeName = item.name
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(selected ? theme.accent.opacity(0.3) : .clear)
                                            .frame(width: 44, height: 44)
                                        item.icon
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 20, height: 20)
                                            .foregroundStyle(selected ? theme.accent : .secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    // Color picker
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(32), spacing: 10), count: 8), spacing: 10) {
                        ForEach(ColorSwatches.teamSwatches.indices, id: \.self) { idx in
                            let c = ColorSwatches.teamSwatches[idx]
                            Button {
                                colorIndex = idx
                            } label: {
                                Circle()
                                    .fill(c)
                                    .overlay(
                                        Circle().strokeBorder(.white.opacity(idx == colorIndex ? 1.0 : 0.0), lineWidth: 2)
                                    )
                                    .frame(width: 26, height: 26)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(theme.palette.surface)

                Section("Players") {
                    if players.isEmpty {
                        Text("No players yet")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(players, id: \.id) { p in
                            HStack {
                                Circle()
                                    .fill(ColorSwatches.teamSwatches[p.colorIndex % ColorSwatches.teamSwatches.count])
                                    .frame(width: 22, height: 22)
                                    .overlay(Text(p.initials).font(.system(size: 10, weight: .bold, design: .rounded)))
                                VStack(alignment: .leading) {
                                    Text(p.displayName)
                                    if let n = p.nickname {
                                        Text(n).font(.caption).foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    players.removeAll { $0.id == p.id }
                                } label: {
                                    Image(systemName: "trash.fill")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        TextField("Name", text: $newPlayerName)
                        TextField("Nickname (optional)", text: $newPlayerNick)
                        Button {
                            let nameSan = Player.sanitized(newPlayerName)
                            guard !nameSan.isEmpty else { return }
                            let p = Player(name: nameSan, nickname: Player.sanitizedEmptyNil(newPlayerNick))
                            players.append(p)
                            newPlayerName = ""
                            newPlayerNick = ""
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listRowBackground(theme.palette.surface)
            }
            .scrollContentBackground(.hidden)
            .background(theme.background)
            .navigationTitle(isEditing ? "Edit Team" : "New Team")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        onFinish(.cancelled)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Create") {
                        let team = buildTeam()
                        if isEditing {
                            onFinish(.updated(team))
                        } else {
                            onFinish(.created(team))
                        }
                        dismiss()
                    }
                    .disabled(Player.sanitized(name).isEmpty)
                }
                if isEditing, let id = teamToEdit?.id {
                    ToolbarItem(placement: .bottomBar) {
                        Button(role: .destructive) {
                            onFinish(.deleted(id))
                            dismiss()
                        } label: {
                            Label("Delete Team", systemImage: "trash.fill")
                        }
                    }
                }
            }
            .onAppear {
                loadInitial()
            }
        }
        .tint(theme.accent)
    }

    // Build / Load
    private func loadInitial() {
        if let t = teamToEdit {
            name = t.name
            sport = t.sport
            badgeName = t.badgeName
            colorIndex = t.normalizedColorIndex
            players = t.players
        } else {
            sport = initialSport ?? .football
            colorIndex = ColorSwatches.teamColorIndex(for: UUID()) % max(1, ColorSwatches.teamSwatches.count)
            badgeName = IconLibrary.teamBadgePickerItems().first?.name ?? "sf:shield.fill"
            players = []
        }
    }

    private func buildTeam() -> Team {
        if let t = teamToEdit {
            return Team(
                id: t.id,
                name: Team.sanitized(name),
                sport: sport,
                colorIndex: colorIndex,
                badgeName: Team.sanitizedBadge(badgeName),
                players: players,
                createdAt: t.createdAt,
                updatedAt: Date()
            )
        } else {
            return Team(
                name: Team.sanitized(name),
                sport: sport,
                colorIndex: colorIndex,
                badgeName: Team.sanitizedBadge(badgeName),
                players: players
            )
        }
    }
}

// MARK: - Small UI bits

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
