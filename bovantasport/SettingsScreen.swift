//
//  SettingsScreen.swift
//  Bovanta:Sport
//
//  Created on 2025-10-14
//

import SwiftUI
import Combine

/// Settings screen: theme (System/Light/Dark), haptics toggle,
/// local data reset, and About section. English-only UI and comments.
public struct SettingsScreen: View {
    // MARK: - Environment
    @EnvironmentObject private var theme: AppTheme
    @EnvironmentObject private var haptics: HapticsManager

    // MARK: - Theme model (local to this screen)
    /// Mirrors the key consumed in BovantaSportApp (`settings.theme.style`)
    private enum ThemeStyle: String, CaseIterable, Hashable {
        case system, light, dark

        var title: String {
            switch self {
            case .system: return "System"
            case .light:  return "Light"
            case .dark:   return "Dark"
            }
        }
    }

    // MARK: - Local UI state
    @State private var pendingTheme: ThemeStyle = .system
    @State private var showResetAlert: Bool = false
    @State private var showDoneToast: Bool = false

    // Persisted toggles; App and managers listen to these keys.
    @AppStorage("settings.hapticsEnabled") private var storedHapticsEnabled: Bool = true
    @AppStorage("settings.theme.style") private var storedThemeStyleRaw: String = ThemeStyle.system.rawValue

    public init() {}

    // MARK: - Body
    public var body: some View {
        Form {
//            appearanceSection
//                .listRowBackground(theme.palette.surface)

            hapticsSection
                .listRowBackground(theme.palette.surface)

            dataSection
                .listRowBackground(theme.palette.surface)

            aboutSection
                .listRowBackground(theme.palette.surface)
        }
        .scrollContentBackground(.hidden)
        .background(theme.background.ignoresSafeArea())
        .navigationTitle("Settings")
        .onAppear {
            // Sync local picker with stored preference
            pendingTheme = ThemeStyle(rawValue: storedThemeStyleRaw) ?? .system
        }
        .toast(isPresented: $showDoneToast) {
            DoneToastView(text: "Done")
        }
    }

    // MARK: - Sections

    // Appearance
    private var appearanceSection: some View {
        Section {
            Picker("Theme", selection: $pendingTheme) {
                ForEach(ThemeStyle.allCases, id: \.self) { style in
                    Text(style.title).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: pendingTheme) { newValue in
                storedThemeStyleRaw = newValue.rawValue
                haptics.select()
            }

            HStack {
                Text("Preview")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(theme.palette.textSecondary)
                Spacer()
                Circle()
                    .fill(theme.accent)
                    .frame(width: 16, height: 16)
                Text(newModeNote)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundColor(theme.palette.textSecondary)
            }
        } header: {
            Text("Appearance")
        } footer: {
            Text("Choose the app theme. “System” follows the device setting.")
        }
    }

    // Haptics
    private var hapticsSection: some View {
        Section {
            Toggle(isOn: Binding(get: {
                storedHapticsEnabled
            }, set: { newVal in
                storedHapticsEnabled = newVal       // Managers observe this key
                if newVal { haptics.light() }
            })) {
                Label("Haptic feedback", systemImage: "dot.radiowaves.left.and.right")
            }

//            Button {
//                haptics.impact(style: .rigid)
//            } label: {
//                Label("Test haptic", systemImage: "hand.tap.fill")
//            }
//            .disabled(!storedHapticsEnabled)
        } header: {
            Text("Haptics")
        } footer: {
            Text("Disable if you don’t want vibration feedback for taps and events.")
        }
    }

    // Data: reset local storage
    private var dataSection: some View {
        Section {
            Button(role: .destructive) {
                showResetAlert = true
            } label: {
                Label("Reset all local data", systemImage: "trash.fill")
            }
            .alert("Reset all data?", isPresented: $showResetAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    StorageService.shared.clearAll()
                    // After clearing, defaults for toggles may also reset; no extra writes needed here.
                    haptics.error()
                    showDoneToast = true
                }
            } message: {
                Text("Teams, matches, and settings will be removed from this device and cannot be recovered.")
            }
        } header: {
            Text("Data")
        } footer: {
            Text("Data is stored locally. No export or cloud sync is used.")
        }
    }

    // About
    private var aboutSection: some View {
        Section {
            HStack {
                appIcon
                VStack(alignment: .leading, spacing: 2) {
//                    Text(appName)
//                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                    Text("Version \(appVersion) (\(appBuild))")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(theme.palette.textSecondary)
                }
                Spacer()
            }

//            Link(destination: URL(string: "https://example.com/support")!) {
//                Label("Support / Feedback", systemImage: "envelope.fill")
//            }

            Link(destination: URL(string: "https://www.termsfeed.com/live/d56e2d37-c28d-44a3-8bdd-f9d69e546925")!) {
                Label("Privacy Policy", systemImage: "lock.shield.fill")
            }
        } header: {
            Text("About")
        } footer: {
            Text("Bovanta:Sport — scores, matches, and basic stats for friendly games.")
        }
    }

    // MARK: - Helpers

    private var newModeNote: String {
        switch pendingTheme {
        case .system: return "Follows system"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
        ?? "Bovanta:Sport"
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    private var appIcon: some View {
        // Square icon preview (dynamic gradient + emblem)
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(ColorSwatches.softVerticalGradient(theme.accent))
                .frame(width: 48, height: 48)
                .shadow(color: ColorSwatches.shadow(for: theme.accent), radius: 6, x: 0, y: 3)
            Image(systemName: "sportscourt.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .foregroundColor(ColorSwatches.bestTextColor(on: theme.accent))
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Small Toast

private struct DoneToastView: View {
    @EnvironmentObject private var theme: AppTheme
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
            Text(text)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(theme.palette.surface.opacity(0.95))
        .foregroundColor(theme.palette.textPrimary)
        .clipShape(Capsule())
        .shadow(radius: 6, y: 3)
    }
}

// MARK: - Tiny toast modifier

private struct ToastModifier<T: View>: ViewModifier {
    @Binding var isPresented: Bool
    let content: () -> T

    func body(content base: Content) -> some View {
        ZStack {
            base
            if isPresented {
                self.content()
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                                isPresented = false
                            }
                        }
                    }
                    .zIndex(1)
                    .padding(.top, 8)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: isPresented)
    }
}

private extension View {
    func toast<T: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> T) -> some View {
        modifier(ToastModifier(isPresented: isPresented, content: content))
    }
}
