import SwiftData
import SwiftUI
import WastlyKit

@main
struct WastlyApp: App {
    @StateObject private var session: SessionStore
    @Environment(\.scenePhase) private var scenePhase

    init() {
        do {
            _session = StateObject(wrappedValue: try SessionStore.bootstrap())
        } catch {
            fatalError("Wastly could not open the local store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .modelContainer(session.container)
                .preferredColorScheme(.light)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background || phase == .inactive {
                session.lockIfNeeded()
            }
        }
    }
}
