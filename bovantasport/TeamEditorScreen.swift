//
//  TeamEditorScreen.swift
//  Bovanta:Sport
//
//  Created on 2025-10-14
//

import SwiftUI
import Combine

/// Полноэкранный редактор команды:
/// - имя, вид спорта
/// - значок (SF Symbols из IconLibrary) и цвет
/// - состав игроков (добавить/удалить/переименовать)
/// - создание новой или редактирование существующей команды
///
/// Использование:
/// NavigationLink { TeamEditorScreen(teamID: existingID) }
/// NavigationLink { TeamEditorScreen() } // создать новую
public struct TeamEditorScreen: View {
    // MARK: - Env
    @EnvironmentObject private var theme: AppTheme
    @EnvironmentObject private var haptics: HapticsManager
    @EnvironmentObject private var teamsRepo: TeamsRepository
    @Environment(\.dismiss) private var dismiss

    // MARK: - Input
    public let teamID: UUID?

    // MARK: - State (form)
    @State private var name: String = ""
    @State private var sport: SportKind = .football
    @State private var badgeName: String = "sf:shield.fill"
    @State private var colorIndex: Int = 0
    @State private var players: [Player] = []

    // Player quick add/edit
    @State private var newPlayerName: String = ""
    @State private var newPlayerNick: String = ""
    @State private var editingPlayerID: UUID? = nil

    // Focus
    @FocusState private var focusField: Field?
    private enum Field { case name, playerName, playerNick }

    // MARK: - Init
    public init(teamID: UUID? = nil) {
        self.teamID = teamID
    }

    // MARK: - Body
    public var body: some View {
        Form {
            identitySection
                .listRowBackground(theme.palette.surface)

            appearanceSection
                .listRowBackground(theme.palette.surface)

            playersSection
                .listRowBackground(theme.palette.surface)

            dangerSection
                .listRowBackground(theme.palette.surface)
        }
        .scrollContentBackground(.hidden)
        .background(theme.background.ignoresSafeArea())
        .navigationTitle(teamID == nil ? "New Team" : "Edit Team")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(teamID == nil ? "Create" : "Save") {
                    saveTeam()
                }
                .disabled(Team.sanitized(name).isEmpty)
            }
        }
        .onAppear {
            loadInitial()
        }
    }

    // MARK: - Sections

    private var identitySection: some View {
        Section("Identity") {
            TextField("Team name", text: $name)
                .textInputAutocapitalization(.words)
                .disableAutocorrection(true)
                .focused($focusField, equals: .name)
                .onSubmit { focusField = .playerName }

            Picker("Sport", selection: $sport) {
                ForEach(SportKind.allCases, id: \.self) { kind in
                    HStack(spacing: 8) {
                        kind.icon
                        Text(kind.label)
                    }
                    .tag(kind)
                }
            }
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Badge")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(theme.palette.textSecondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(IconLibrary.teamBadgePickerItems(), id: \.name) { item in
                            let isSel = badgeName == item.name
                            Button {
                                badgeName = item.name
                                haptics.select()
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(isSel ? theme.accent.opacity(0.25) : .clear)
                                        .frame(width: 44, height: 44)
                                    item.icon
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 20, height: 20)
                                        .foregroundStyle(isSel ? theme.accent : .secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Color")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(theme.palette.textSecondary)

                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(30), spacing: 10), count: 10),
                    spacing: 10
                ) {
                    ForEach(ColorSwatches.teamSwatches.indices, id: \.self) { idx in
                        let c = ColorSwatches.teamSwatches[idx]
                        Button {
                            colorIndex = idx
                            haptics.select()
                        } label: {
                            Circle()
                                .fill(c)
                                .overlay(
                                    Circle()
                                        .strokeBorder(.white.opacity(idx == colorIndex ? 1.0 : 0.0), lineWidth: 2)
                                )
                                .frame(width: 24, height: 24)
                                .shadow(radius: 1, y: 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 4)
            }

            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(ColorSwatches.ringGradient(ColorSwatches.teamSwatches[colorIndex % ColorSwatches.teamSwatches.count]))
                        .frame(width: 40, height: 40)
                    IconLibrary.teamBadge(named: badgeName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                        .foregroundStyle(ColorSwatches.bestTextColor(on: ColorSwatches.teamSwatches[colorIndex % ColorSwatches.teamSwatches.count]))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Preview")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(theme.palette.textSecondary)
                    Text(name.isEmpty ? "Team Name" : name)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                }
                Spacer()
                Chip(text: sport.shortLabel, icon: sport.icon, color: sport.accent)
            }
            .padding(.top, 2)
        }
    }

    private var playersSection: some View {
        Section {
            if players.isEmpty {
                Text("No players yet").foregroundColor(.secondary)
            } else {
                ForEach(players, id: \.id) { p in
                    HStack {
                        Circle()
                            .fill(ColorSwatches.teamSwatches[p.colorIndex % ColorSwatches.teamSwatches.count])
                            .frame(width: 24, height: 24)
                            .overlay(
                                Text(p.initials)
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                            )
                        VStack(alignment: .leading) {
                            Text(p.displayName)
                            if let n = p.nickname {
                                Text(n).font(.caption).foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        Button {
                            editingPlayerID = p.id
                            newPlayerName = p.name
                            newPlayerNick = p.nickname ?? ""
                            focusField = .playerName
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.plain)
                        Button(role: .destructive) {
                            players.removeAll { $0.id == p.id }
                            haptics.warning()
                        } label: {
                            Image(systemName: "trash.fill")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(editingPlayerID == nil ? "Add player" : "Edit player")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(theme.palette.textSecondary)
                HStack(spacing: 8) {
                    TextField("Name", text: $newPlayerName)
                        .focused($focusField, equals: .playerName)
                        .onSubmit { focusField = .playerNick }
                    TextField("Nickname (optional)", text: $newPlayerNick)
                        .focused($focusField, equals: .playerNick)
                        .onSubmit { applyPlayer() }
                    Button {
                        applyPlayer()
                    } label: {
                        Image(systemName: editingPlayerID == nil ? "plus.circle.fill" : "checkmark.circle.fill")
                    }.buttonStyle(.plain)
                    if editingPlayerID != nil {
                        Button {
                            cancelPlayerEdit()
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.top, 4)
        } header: {
            Text("Players")
        } footer: {
            Text("Игроки необязательны — можно вести счёт без состава.")
                .font(.caption2)
                .foregroundColor(theme.palette.textSecondary)
        }
    }

    private var dangerSection: some View {
        Section("Danger Zone") {
            if let id = teamID {
                Button(role: .destructive) {
                    teamsRepo.delete(teamID: id)
                    haptics.error()
                    dismiss()
                } label: {
                    Label("Delete Team", systemImage: "trash.fill")
                }
            } else {
                Text("The team will be created locally and stored on this device.")
                    .font(.caption)
                    .foregroundColor(theme.palette.textSecondary)
            }
        }
    }

    // MARK: - Actions

    private func loadInitial() {
        if let id = teamID, let t = teamsRepo.team(by: id) {
            name = t.name
            sport = t.sport
            badgeName = t.badgeName
            colorIndex = t.normalizedColorIndex
            players = t.players
        } else {
            // Defaults for new team
            sport = .football
            badgeName = teamsRepo.suggestBadgeName()
            colorIndex = teamsRepo.suggestColorIndex()
            players = []
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                focusField = .name
            }
        }
    }

    private func saveTeam() {
        let sanitized = Team.sanitized(name)
        guard !sanitized.isEmpty else { return }

        if let id = teamID, let existing = teamsRepo.team(by: id) {
            let updated = Team(
                id: existing.id,
                name: sanitized,
                sport: sport,
                colorIndex: colorIndex,
                badgeName: Team.sanitizedBadge(badgeName),
                players: players,
                createdAt: existing.createdAt,
                updatedAt: Date()
            )
            teamsRepo.update(updated)
            haptics.success()
        } else {
            _ = teamsRepo.createTeam(
                name: sanitized,
                sport: sport,
                badgeName: Team.sanitizedBadge(badgeName),
                colorIndex: colorIndex,
                players: players
            )
            haptics.success()
        }
        dismiss()
    }

    private func applyPlayer() {
        let nameSan = Player.sanitized(newPlayerName)
        guard !nameSan.isEmpty else { return }
        let nickSan = Player.sanitizedEmptyNil(newPlayerNick)

        if let id = editingPlayerID, let idx = players.firstIndex(where: { $0.id == id }) {
            players[idx] = players[idx].withName(nameSan).withNickname(nickSan)
        } else {
            players.append(Player(name: nameSan, nickname: nickSan))
        }
        newPlayerName = ""
        newPlayerNick = ""
        editingPlayerID = nil
        haptics.light()
    }

    private func cancelPlayerEdit() {
        newPlayerName = ""
        newPlayerNick = ""
        editingPlayerID = nil
        haptics.soft()
    }
}

// MARK: - Small reusable chip

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
