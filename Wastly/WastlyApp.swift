import SwiftData
import SwiftUI
import WastlyKit

@main
struct WastlyApp: App {
    @StateObject private var session: SessionStore
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let bootstrapped: SessionStore
        do {
            bootstrapped = try SessionStore.bootstrap()
        } catch {
            fatalError("Wastly could not open the local store: \(error)")
        }
        _session = StateObject(wrappedValue: bootstrapped)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .modelContainer(session.container)
                .preferredColorScheme(.light)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active:
                Task { await session.applicationDidBecomeActive() }
            case .inactive:
                session.lockForPrivacy()
            case .background:
                session.lockForBackground()
            @unknown default:
                session.lockForPrivacy()
            }
        }
    }
}
