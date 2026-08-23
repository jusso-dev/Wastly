import SwiftData
import SwiftUI
import WastlyKit

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var session: SessionStore
    @Query private var settingsRows: [AppSettings]
    @Query private var catalogState: [CatalogState]
    @State private var showingClearCacheConfirmation = false
    @State private var showingRestoreConfirmation = false
    @State private var cacheMessage: String?

    private var settings: AppSettings {
        SessionStore.settings(in: context)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Energy") {
                    Picker("Unit", selection: unitBinding) {
                        Text("kJ").tag(EnergyUnit.kilojoules)
                        Text("kcal").tag(EnergyUnit.kilocalories)
                    }
                    .pickerStyle(.segmented)
                }
                Section("Privacy") {
                    Toggle("Face ID lock", isOn: faceBinding)
                }
                Section("Optional online facts") {
                    Toggle("Generate extra facts online", isOn: boolBinding(\.llmEnabled))
                    if settings.llmEnabled {
                        Text("Only aggregate days, eaten grams, wasted grams, top food, and the child’s first name are sent.")
                            .font(.wastlyCaption)
                        if session.factGenerator == nil {
                            Text("No fact service is configured in this build. Offline facts will continue to appear.")
                                .font(.wastlyCaption)
                                .foregroundStyle(WastlyTheme.muted)
                        }
                    } else {
                        Text("Off by default. Offline facts do not need a key or internet connection.")
                            .font(.wastlyCaption)
                            .foregroundStyle(WastlyTheme.muted)
                    }
                }
                Section("Optional cloud plate match") {
                    Toggle("Send a cropped plate photo", isOn: boolBinding(\.ocrCloudEnabled))
                    if settings.ocrCloudEnabled {
                        Text("Only a compressed centre crop is sent. Child details, notes, and original photo metadata are excluded.")
                            .font(.wastlyCaption)
                        if session.plateMatcher == nil {
                            Text("No plate matching service is configured in this build.")
                                .font(.wastlyCaption)
                                .foregroundStyle(WastlyTheme.muted)
                        }
                    } else {
                        Text("Off by default. On-device label reading still works without this.")
                            .font(.wastlyCaption)
                            .foregroundStyle(WastlyTheme.muted)
                    }
                }
                Section("Backup") {
                    Toggle("iCloud backup", isOn: backupBinding)
                    Toggle("Password on the backup", isOn: boolBinding(\.backupPasswordEnabled))
                    Text("Profiles, measurements, diary logs, custom foods, and settings are saved privately to your Apple ID. Downloaded food data is not included.")
                        .font(.wastlyCaption)
                        .foregroundStyle(WastlyTheme.muted)
                    if let at = settings.lastBackupAt {
                        Text("Last backup \(at.formatted(date: .abbreviated, time: .shortened))")
                            .font(.wastlyCaption)
                    } else {
                        Text("No backup yet.")
                            .font(.wastlyCaption)
                    }
                    Button {
                        Task { await session.backupNow() }
                    } label: {
                        Label("Backup now", systemImage: "icloud.and.arrow.up")
                    }
                    .disabled(!settings.iCloudBackupEnabled || session.backupIsRunning)
                    .accessibilityIdentifier("settings.backupNow")

                    Button {
                        showingRestoreConfirmation = true
                    } label: {
                        Label("Restore from iCloud", systemImage: "icloud.and.arrow.down")
                    }
                    .disabled(session.backupIsRunning)
                    .accessibilityIdentifier("settings.restoreBackup")

                    if session.backupIsRunning {
                        HStack {
                            ProgressView()
                            Text("Contacting iCloud…")
                        }
                        .font(.wastlyCaption)
                    }
                    if let message = session.backupMessage {
                        Text(message)
                            .font(.wastlyCaption)
                            .foregroundStyle(WastlyTheme.muted)
                            .accessibilityIdentifier("settings.backupMessage")
                    }
                }
                Section("Catalog") {
                    if let at = settings.lastCatalogSyncAt {
                        Text("Last catalog update \(at.formatted(date: .abbreviated, time: .shortened))")
                    } else {
                        Text("Using the bundled seed until a catalog pull lands.")
                    }
                    Text("About \(settings.catalogBytesOnDisk / 1024) KB on disk")
                        .font(.wastlyCaption)
                    Button("Clear downloaded food cache", role: .destructive) {
                        showingClearCacheConfirmation = true
                    }
                    Text("Custom foods and diary logs are never removed.")
                        .font(.wastlyCaption)
                    if let cacheMessage {
                        Text(cacheMessage)
                            .font(.wastlyCaption)
                            .foregroundStyle(WastlyTheme.muted)
                    }
                }
                Section("About") {
                    Text("Logs stay on this iPhone. Backup uses your iCloud. Food lookup, online facts, and plate matching use only the network options described above. No ads. No analytics.")
                        .font(.wastlyCaption)
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Settings")
        }
        .confirmationDialog(
            "Clear downloaded food cache?",
            isPresented: $showingClearCacheConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear downloaded cache", role: .destructive) {
                clearFoodCache()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Recent provider lookups will need internet again. Custom foods and diary logs stay on this iPhone.")
        }
        .confirmationDialog(
            "Replace this iPhone’s diary?",
            isPresented: $showingRestoreConfirmation,
            titleVisibility: .visible
        ) {
            Button("Restore iCloud backup", role: .destructive) {
                Task { await session.restoreFromICloud() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Child profiles, measurements, diary logs, custom foods, and settings on this iPhone will be replaced. Downloaded food data stays local.")
        }
    }

    private var unitBinding: Binding<EnergyUnit> {
        Binding(
            get: { settings.energyUnit },
            set: { new in
                settings.energyUnit = new
                try? context.save()
            }
        )
    }

    private var faceBinding: Binding<Bool> {
        Binding(
            get: { settings.faceIDEnabled },
            set: { new in
                settings.faceIDEnabled = new
                try? context.save()
                if !new { session.isLocked = false }
            }
        )
    }

    private var backupBinding: Binding<Bool> {
        Binding(
            get: { settings.iCloudBackupEnabled },
            set: { enabled in
                settings.iCloudBackupEnabled = enabled
                try? context.save()
                session.backupMessage = nil
                if enabled {
                    Task { await session.backupNow() }
                }
            }
        )
    }

    private func boolBinding(_ keyPath: ReferenceWritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { new in
                settings[keyPath: keyPath] = new
                try? context.save()
            }
        )
    }

    private func clearFoodCache() {
        Task {
            do {
                let removed = try await session.store.clearCacheLeavingCustomAndLogs()
                cacheMessage = removed == 1
                    ? "Removed 1 downloaded food."
                    : "Removed \(removed) downloaded foods."
            } catch {
                cacheMessage = "Couldn’t clear the cache. Check available storage and try again."
            }
        }
    }
}
