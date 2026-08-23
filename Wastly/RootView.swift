import SwiftData
import SwiftUI
import WastlyKit

struct RootView: View {
    @EnvironmentObject private var session: SessionStore
    @Query(sort: \Child.createdAt) private var children: [Child]
    @Query private var settingsRows: [AppSettings]

    var body: some View {
        Group {
            if session.showingOnboarding || children.isEmpty {
                OnboardingView()
            } else if session.isLocked {
                LockView()
            } else {
                MainTabs()
            }
        }
        .modifier(PaperBackground())
        .tint(WastlyTheme.sage)
        .onAppear {
            if session.selectedChildID == nil {
                session.selectedChildID = children.first?.id
            }
            session.showingOnboarding = children.isEmpty
        }
        .onChange(of: children.count) { _, count in
            session.showingOnboarding = count == 0
            if session.selectedChildID == nil {
                session.selectedChildID = children.first?.id
            }
        }
    }
}

struct MainTabs: View {
    @State private var showingLog = false

    var body: some View {
        TabView {
            TodayView(showingLog: $showingLog)
                .tabItem { Label("Today", systemImage: "sun.max") }
            DiaryView()
                .tabItem { Label("Diary", systemImage: "book") }
            FactsView()
                .tabItem { Label("Facts", systemImage: "chart.bar") }
            KidsView()
                .tabItem { Label("Kids", systemImage: "figure.and.child.holdinghands") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .toolbarBackground(WastlyTheme.surface, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .sheet(isPresented: $showingLog) {
            LogSheet()
        }
    }
}
