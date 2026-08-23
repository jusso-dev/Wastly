import SwiftData
import SwiftUI
import WastlyKit

struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var session: SessionStore
    @State private var name = ""
    @State private var dob = Calendar.current.date(byAdding: .year, value: -4, to: .now) ?? .now
    @State private var heightText = ""
    @State private var weightText = ""
    @State private var faceID = false
    @State private var backup = false
    @State private var backupPassword = false
    @State private var backupPasswordText = ""
    @State private var backupPasswordConfirmation = ""
    @State private var isSaving = false
    @State private var saveError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Wastly")
                    .font(.wastlyDayTotal)
                    .foregroundStyle(WastlyTheme.ink)
                Text("A private diary of what they ate and what they left.")
                    .font(.wastlyBody)
                    .foregroundStyle(WastlyTheme.ink)
                Text("Logs stay on this iPhone. Only the cloud features you choose—such as iCloud backup and food lookup—use the internet.")
                    .font(.wastlyBody)
                    .foregroundStyle(WastlyTheme.muted)

                JournalCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("First child")
                            .font(.wastlyCaption)
                            .foregroundStyle(WastlyTheme.muted)
                        TextField("First name", text: $name)
                            .font(.wastlyBody)
                            .textInputAutocapitalization(.words)
                        DatePicker("Date of birth", selection: $dob, displayedComponents: .date)
                            .font(.wastlyBody)
                        TextField("Height in cm (optional)", text: $heightText)
                            .keyboardType(.decimalPad)
                        TextField("Weight in kg (optional)", text: $weightText)
                            .keyboardType(.decimalPad)
                    }
                }

                JournalCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Lock the diary with Face ID", isOn: $faceID)
                        Toggle("iCloud backup", isOn: $backup)
                        Toggle("Password on the backup", isOn: $backupPassword)
                            .disabled(!backup)
                        if backup && backupPassword {
                            SecureField("Backup password", text: $backupPasswordText)
                                .textContentType(.newPassword)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .accessibilityIdentifier("onboarding.backupPassword")
                            SecureField("Confirm backup password", text: $backupPasswordConfirmation)
                                .textContentType(.newPassword)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .accessibilityIdentifier("onboarding.backupPasswordConfirmation")
                            Text("Use at least 8 non-space characters. Wastly cannot recover a forgotten backup password.")
                                .font(.wastlyCaption)
                                .foregroundStyle(WastlyTheme.muted)
                        }
                    }
                    .font(.wastlyBody)
                }

                Button {
                    Task { await save() }
                } label: {
                    Group {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Open Today")
                        }
                    }
                        .font(.wastlyBody.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(canSave ? WastlyTheme.sage : WastlyTheme.hairline)
                        .foregroundStyle(canSave ? WastlyTheme.onAccent : WastlyTheme.muted)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .disabled(!canSave)
            }
            .padding(20)
        }
        .alert("Couldn’t open Today", isPresented: showingSaveError) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "Nothing was saved. Try again.")
        }
        .onChange(of: backup) { _, enabled in
            if !enabled {
                backupPassword = false
                backupPasswordText = ""
                backupPasswordConfirmation = ""
            }
        }
    }

    private var canSave: Bool {
        guard !isSaving,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return false }
        guard backup && backupPassword else { return true }
        return BackupPasswordPolicy.isValid(backupPasswordText)
            && backupPasswordText == backupPasswordConfirmation
    }

    private var showingSaveError: Binding<Bool> {
        Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )
    }

    private func save() async {
        guard canSave else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let child = try OnboardingStore.save(
                OnboardingInput(
                    firstName: name,
                    dateOfBirth: dob,
                    heightCentimetres: Double(heightText),
                    weightKilograms: Double(weightText),
                    faceIDEnabled: faceID,
                    iCloudBackupEnabled: backup,
                    backupPasswordEnabled: false
                ),
                in: context
            )
            session.selectedChildID = child.id
            session.isLocked = false
            if backupPassword {
                let passwordSaved = await session.setBackupPassword(backupPasswordText)
                if !passwordSaved, session.backupPasswordPrompt == nil {
                    session.backupPasswordPrompt = .set
                }
            } else if backup {
                await session.backupNow()
            }
            session.showingOnboarding = false
        } catch {
            saveError = "Nothing was saved. Check available storage and try again."
        }
    }
}
