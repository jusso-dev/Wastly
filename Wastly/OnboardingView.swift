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
                Text("Logs stay on this iPhone. Backup uses your iCloud. Food lookup is the only thing that goes to the internet.")
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
                    }
                    .font(.wastlyBody)
                }

                Button(action: save) {
                    Text("Open Today")
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
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var showingSaveError: Binding<Bool> {
        Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )
    }

    private func save() {
        do {
            let child = try OnboardingStore.save(
                OnboardingInput(
                    firstName: name,
                    dateOfBirth: dob,
                    heightCentimetres: Double(heightText),
                    weightKilograms: Double(weightText),
                    faceIDEnabled: faceID,
                    iCloudBackupEnabled: backup,
                    backupPasswordEnabled: backupPassword
                ),
                in: context
            )
            session.selectedChildID = child.id
            session.showingOnboarding = false
            session.isLocked = false
        } catch {
            saveError = "Nothing was saved. Check available storage and try again."
        }
    }
}
