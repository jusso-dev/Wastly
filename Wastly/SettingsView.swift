import Foundation
import SwiftData
import SwiftUI
import WastlyKit

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var session: SessionStore
    @Query private var settingsRows: [AppSettings]
    @State private var showingRemovePasswordConfirmation = false

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
                    .accessibilityIdentifier("settings.energyUnit")
                }
                Section("Privacy") {
                    Toggle("Face ID or passcode lock", isOn: faceBinding)
                        .accessibilityIdentifier("settings.diaryLock")
                    Text("When enabled, Wastly hides the diary whenever the app leaves the foreground.")
                        .font(.wastlyCaption)
                        .foregroundStyle(WastlyTheme.muted)
                }
                Section("On-device AI facts") {
                    Toggle("Generate extra facts on this iPhone", isOn: boolBinding(\.llmEnabled))
                        .accessibilityIdentifier("settings.onDeviceFacts")
                    if settings.llmEnabled {
                        Text(
                            "Apple’s iOS 26 language model uses diary totals, top food, and first name only "
                                + "on this device. Nothing is sent to an AI service."
                        )
                            .font(.wastlyCaption)
                        Text(session.onDeviceFactAvailability.settingsDescription)
                            .font(.wastlyCaption)
                            .foregroundStyle(WastlyTheme.muted)
                    } else {
                        Text("Off by default. Deterministic facts remain available on every supported iPhone.")
                            .font(.wastlyCaption)
                            .foregroundStyle(WastlyTheme.muted)
                    }
                }
                Section("Optional cloud plate match") {
                    Toggle("Send a cropped plate photo", isOn: boolBinding(\.ocrCloudEnabled))
                        .accessibilityIdentifier("settings.cloudPlateMatch")
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
                        .accessibilityIdentifier("settings.iCloudBackup")
                    LabeledContent("Backup password") {
                        Text(settings.backupPasswordEnabled ? "On" : "Off")
                            .foregroundStyle(settings.backupPasswordEnabled ? WastlyTheme.sage : WastlyTheme.muted)
                    }
                    if settings.backupPasswordEnabled {
                        Button("Change backup password") {
                            session.backupPasswordPrompt = .change
                        }
                        .disabled(session.backupIsRunning)
                        Button("Remove backup password", role: .destructive) {
                            showingRemovePasswordConfirmation = true
                        }
                        .disabled(session.backupIsRunning)
                    } else {
                        Button("Add backup password") {
                            session.backupPasswordPrompt = .set
                        }
                        .disabled(!settings.iCloudBackupEnabled || session.backupIsRunning)
                    }
                    Text("The password stays in this device’s Keychain and is never stored in iCloud. If you forget it, that backup cannot be recovered; the diary on this iPhone stays safe.")
                        .font(.wastlyCaption)
                        .foregroundStyle(WastlyTheme.muted)
                    Text("Profiles, measurements, diary logs, custom foods, and settings are saved privately to your Apple ID. Downloaded food data is not included.")
                        .font(.wastlyCaption)
                        .foregroundStyle(WastlyTheme.muted)
                    if let at = settings.lastBackupAt {
                        Text("Last backup \(at.formatted(date: .abbreviated, time: .shortened))")
                            .font(.wastlyCaption)
                            .accessibilityIdentifier("settings.lastBackup")
                    } else {
                        Text("No backup yet.")
                            .font(.wastlyCaption)
                            .accessibilityIdentifier("settings.lastBackup")
                    }
                    Button {
                        Task { await session.backupNow() }
                    } label: {
                        Label("Backup now", systemImage: "icloud.and.arrow.up")
                    }
                    .disabled(!settings.iCloudBackupEnabled || session.backupIsRunning)
                    .accessibilityIdentifier("settings.backupNow")

                    Button {
                        Task { await session.offerRestoreFromICloud() }
                    } label: {
                        Label("Restore or merge from iCloud", systemImage: "icloud.and.arrow.down")
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
                CatalogSettingsSection()
                Section("About") {
                    Text("Logs stay on this iPhone. Backup uses your iCloud. AI facts run on this iPhone. Food lookup and plate matching use only the network options described above. No ads. No analytics.")
                        .font(.wastlyCaption)
                        .accessibilityIdentifier("settings.privacySummary")
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Settings")
        }
        .confirmationDialog(
            "Remove the backup password?",
            isPresented: $showingRemovePasswordConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove password", role: .destructive) {
                Task { await session.removeBackupPassword() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Wastly will replace the encrypted iCloud envelope with an unencrypted private backup, then remove the password from this iPhone.")
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
                session.diaryLockSettingChanged(enabled: new)
                if new {
                    Task { await session.unlock() }
                }
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

}

struct BackupRestoreOfferSheet: View {
    @EnvironmentObject private var session: SessionStore
    let offer: BackupRestoreOffer
    @State private var password = ""
    @State private var showingReplaceConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(offer.isFirstLaunch
                        ? "Wastly found a private iCloud backup. Nothing will be imported until you choose."
                        : "Choose how this private iCloud backup should be imported.")
                        .font(.wastlyBody)
                    LabeledContent("Backup date") {
                        Text(offer.createdAt.formatted(date: .abbreviated, time: .shortened))
                    }
                    LabeledContent("Password") {
                        Text(offer.passwordProtected ? "Required" : "Not set")
                            .foregroundStyle(offer.passwordProtected ? WastlyTheme.sage : WastlyTheme.muted)
                    }
                }

                if offer.passwordProtected {
                    Section("Unlock backup") {
                        SecureField("Backup password", text: $password)
                            .textContentType(.password)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("restore.password")
                        Text("The password is checked locally. A wrong password leaves this iPhone’s diary unchanged.")
                            .font(.wastlyCaption)
                            .foregroundStyle(WastlyTheme.muted)
                    }
                }

                Section("Import choice") {
                    Button {
                        Task { await restore(mode: .merge) }
                    } label: {
                        restoreChoiceLabel(
                            title: "Merge backup",
                            detail: "Keep local diary rows and add backup rows whose IDs are missing.",
                            systemImage: "arrow.triangle.merge"
                        )
                    }
                    .disabled(!canRestore)
                    .accessibilityIdentifier("restore.merge")

                    Button(role: .destructive) {
                        showingReplaceConfirmation = true
                    } label: {
                        restoreChoiceLabel(
                            title: "Replace this diary",
                            detail: "Remove local profiles, measurements, diary rows, custom foods, and settings, then use the backup.",
                            systemImage: "arrow.clockwise.icloud"
                        )
                    }
                    .disabled(!canRestore)
                    .accessibilityIdentifier("restore.replace")
                }

                if session.backupIsRunning {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Importing iCloud backup…")
                        }
                    }
                }
                if let message = session.backupMessage {
                    Section {
                        Text(message)
                            .font(.wastlyCaption)
                            .foregroundStyle(WastlyTheme.muted)
                            .accessibilityIdentifier("restore.message")
                    }
                }
            }
            .navigationTitle(offer.isFirstLaunch ? "Restore backup?" : "Import backup")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(offer.isFirstLaunch ? "Start fresh" : "Cancel") {
                        session.cancelRestoreOffer()
                    }
                    .disabled(session.backupIsRunning)
                    .accessibilityIdentifier("restore.cancel")
                }
            }
        }
        .confirmationDialog(
            "Replace this iPhone’s diary?",
            isPresented: $showingReplaceConfirmation,
            titleVisibility: .visible
        ) {
            Button("Replace with iCloud backup", role: .destructive) {
                Task { await restore(mode: .replace) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Local profiles, measurements, diary rows, custom foods, and settings will be replaced. Downloaded food data stays local.")
        }
    }

    private var canRestore: Bool {
        !session.backupIsRunning && (!offer.passwordProtected || !password.isEmpty)
    }

    private func restoreChoiceLabel(
        title: String,
        detail: String,
        systemImage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.wastlyBody.weight(.semibold))
            Text(detail)
                .font(.wastlyCaption)
                .foregroundStyle(WastlyTheme.muted)
                .multilineTextAlignment(.leading)
        }
        .padding(.vertical, 4)
    }

    private func restore(mode: RestoreMode) async {
        _ = await session.restoreFromICloud(
            mode: mode,
            password: offer.passwordProtected ? password : nil
        )
    }
}

struct BackupPasswordSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionStore
    let purpose: BackupPasswordPromptPurpose
    @State private var password = ""
    @State private var confirmation = ""
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(explanation)
                        .font(.wastlyBody)
                    SecureField("Backup password", text: $password)
                        .textContentType(purpose == .restore ? .password : .newPassword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("backupPassword.password")
                    if purpose != .restore {
                        SecureField("Confirm password", text: $confirmation)
                            .textContentType(.newPassword)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("backupPassword.confirmation")
                    }
                }
                Section {
                    Text("Wastly keeps the password only in this device’s Keychain. It is never placed in iCloud. A forgotten password cannot be recovered, but local diary data remains available.")
                        .font(.wastlyCaption)
                        .foregroundStyle(WastlyTheme.muted)
                    if let message = session.backupMessage {
                        Text(message)
                            .font(.wastlyCaption)
                            .foregroundStyle(WastlyTheme.muted)
                            .accessibilityIdentifier("backupPassword.message")
                    }
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        session.backupPasswordPrompt = nil
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(submitLabel) {
                        Task { await submit() }
                    }
                    .disabled(!canSubmit || isSubmitting || session.backupIsRunning)
                    .accessibilityIdentifier("backupPassword.submit")
                }
            }
        }
    }

    private var title: String {
        switch purpose {
        case .set: "Protect backup"
        case .change: "Change password"
        case .restore: "Unlock backup"
        }
    }

    private var explanation: String {
        switch purpose {
        case .set:
            "Choose a password to encrypt the next iCloud backup."
        case .change:
            "Choose a new password. Wastly will replace the current iCloud backup with one encrypted by it."
        case .restore:
            "Enter the password that was used when this iCloud backup was created."
        }
    }

    private var submitLabel: String {
        purpose == .restore ? "Restore" : "Save"
    }

    private var canSubmit: Bool {
        if purpose == .restore { return !password.isEmpty }
        return BackupPasswordPolicy.isValid(password) && password == confirmation
    }

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        let succeeded: Bool
        switch purpose {
        case .set, .change:
            succeeded = await session.setBackupPassword(password)
        case .restore:
            succeeded = await session.restoreFromICloud(password: password)
        }
        if succeeded { dismiss() }
    }
}
