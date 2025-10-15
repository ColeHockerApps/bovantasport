//
//  BovantaSportApp.swift
//  Bovanta:Sport
//
//  Created on 2025-10-14
//

import SwiftUI

@main
public struct BovantaSportApp: App {
    // Core environment objects
    @StateObject private var theme = AppTheme()
    @StateObject private var haptics = HapticsManager.shared
    @StateObject private var teamsRepo = TeamsRepository()
    @StateObject private var matchesRepo = MatchesRepository()
    @StateObject private var statsService = StatsService()

    @AppStorage("settings.theme.style") private var themeStyleRaw: String = "dark"

    @State private var selectedTab: AppTab = .home

    
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    final class AppDelegate: NSObject, UIApplicationDelegate {
        func application(_ application: UIApplication,
                         supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
            if OrientationGate.allowAll {
                return [.portrait, .landscapeLeft, .landscapeRight]
            } else {
                return [.portrait]
            }
        }
    }
    
    
    public init() {
        
        NotificationCenter.default.post(name: Notification.Name("art.icon.loading.start"), object: nil)
        IconSettings.shared.attach()
        
        UITabBar.appearance().isTranslucent = true
    }

    
    
    
    public var body: some Scene {
        WindowGroup {
            
            TabSettingsView{
                RootTabView(selectedTab: $selectedTab)
                    .environmentObject(theme)
                    .environmentObject(haptics)
                    .environmentObject(teamsRepo)
                    .environmentObject(matchesRepo)
                    .environmentObject(statsService)
                    .preferredColorScheme(themeStyleRaw == "dark" ? .dark :
                                            themeStyleRaw == "light" ? .light : nil)
                
                
                    .onAppear {
                                        
                        ReviewNudge.shared.schedule(after: 60)
                                 
                    }
                
                
                
            }
            
            .onAppear {
                OrientationGate.allowAll = false
            }
            
            
            
        }
        
        
        
        
        
        
    }
}





// MARK: - Tab Enum

enum AppTab: Hashable {
    case home, teams, score, stats, settings

    var title: String {
        switch self {
        case .home: return "Home"
        case .teams: return "Teams"
        case .score: return "Score"
        case .stats: return "Stats"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house.fill"
        case .teams: return "person.2.fill"
        case .score: return "sportscourt.fill"
        case .stats: return "chart.bar.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

// MARK: - Root Tab View

private struct RootTabView: View {
    @EnvironmentObject private var theme: AppTheme
    @Binding var selectedTab: AppTab

    var body: some View {
        
        TabView(selection: $selectedTab) {
            NavigationStack { HomeScreen() }
                .tabItem { Label(AppTab.home.title, systemImage: AppTab.home.systemImage) }
                .tag(AppTab.home)

            NavigationStack { TeamsScreen() }
                .tabItem { Label(AppTab.teams.title, systemImage: AppTab.teams.systemImage) }
                .tag(AppTab.teams)

            // ⬇️ Use a launcher that decides what to show
            NavigationStack { ScoreTabRoot() }
                .tabItem { Label(AppTab.score.title, systemImage: AppTab.score.systemImage) }
                .tag(AppTab.score)

            NavigationStack { StatsScreen() }
                .tabItem { Label(AppTab.stats.title, systemImage: AppTab.stats.systemImage) }
                .tag(AppTab.stats)

            NavigationStack { SettingsScreen() }
                .tabItem { Label(AppTab.settings.title, systemImage: AppTab.settings.systemImage) }
                .tag(AppTab.settings)
        }
        .tint(theme.accent)
        .background(theme.background.ignoresSafeArea())
    }
}



private struct ScoreTabRoot: View {
    @EnvironmentObject private var matchesRepo: MatchesRepository

    var body: some View {
        if let latest = matchesRepo.recent(limit: 1).first {
            ScoreboardScreen(matchID: latest.id)
        } else {
            MatchSetupScreen()
                .navigationTitle("New Match")
        }
    }
}
