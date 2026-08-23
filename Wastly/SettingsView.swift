import SwiftData
import SwiftUI
import WastlyKit

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var session: SessionStore
    @Query private var settingsRows: [AppSettings]
    @Query private var catalogState: [CatalogState]

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
                    Toggle("Cloud plate match", isOn: boolBinding(\.ocrCloudEnabled))
                    Toggle("LLM facts", isOn: boolBinding(\.llmEnabled))
                    Toggle("Face ID lock", isOn: faceBinding)
                }
                Section("Backup") {
                    Toggle("iCloud backup", isOn: boolBinding(\.iCloudBackupEnabled))
                    Toggle("Password on the backup", isOn: boolBinding(\.backupPasswordEnabled))
                    if let at = settings.lastBackupAt {
                        Text("Last backup \(at.formatted(date: .abbreviated, time: .shortened))")
                            .font(.wastlyCaption)
                    } else {
                        Text("No backup yet.")
                            .font(.wastlyCaption)
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
                    Button("Clear food cache") {
                        Task { await session.store.clearCacheLeavingCustomAndLogs() }
                    }
                }
                Section("About") {
                    Text("Logs stay on this iPhone. Backup uses your iCloud. Food lookup is the only thing that goes to the internet. No ads. No analytics.")
                        .font(.wastlyCaption)
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Settings")
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

    private func boolBinding(_ keyPath: ReferenceWritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { new in
                settings[keyPath: keyPath] = new
                try? context.save()
            }
        )
    }
}
