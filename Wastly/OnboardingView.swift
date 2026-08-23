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
                        .foregroundStyle(canSave ? Color.white : WastlyTheme.muted)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .disabled(!canSave)
            }
            .padding(20)
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let child = Child(firstName: trimmed, dateOfBirth: dob)
        context.insert(child)
        if let cm = Double(heightText), let kg = Double(weightText) {
            context.insert(MeasurementPoint(heightCentimetres: cm, weightKilograms: kg, child: child))
        } else if let cm = Double(heightText) {
            context.insert(MeasurementPoint(heightCentimetres: cm, child: child))
        } else if let kg = Double(weightText) {
            context.insert(MeasurementPoint(weightKilograms: kg, child: child))
        }
        let settings = SessionStore.settings(in: context)
        settings.faceIDEnabled = faceID
        settings.iCloudBackupEnabled = backup
        settings.backupPasswordEnabled = backup && backupPassword
        try? context.save()
        session.selectedChildID = child.id
        session.showingOnboarding = false
        session.isLocked = false
    }
}
