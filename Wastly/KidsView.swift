import SwiftData
import SwiftUI
import WastlyKit

struct KidsView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var session: SessionStore
    @Query(sort: \Child.createdAt) private var children: [Child]
    @State private var editorTarget: ChildEditorTarget?
    @State private var pendingDelete: Child?
    @State private var deleteError: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        editorTarget = .new
                    } label: {
                        Label("Add child", systemImage: "person.badge.plus")
                            .font(.wastlyBody.weight(.semibold))
                    }
                } footer: {
                    Text("Each child has a private diary and their own measurement history.")
                }

                Section("Children") {
                    ForEach(children, id: \.id) { child in
                        childRow(child)
                            .swipeActions {
                                Button("Delete", role: .destructive) {
                                    pendingDelete = child
                                }
                            }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Kids")
            .sheet(item: $editorTarget) { target in
                NavigationStack {
                    switch target {
                    case .new:
                        ChildProfileEditor(child: nil, onSaved: didSave)
                    case .existing(let id):
                        if let child = children.first(where: { $0.id == id }) {
                            ChildProfileEditor(child: child, onSaved: didSave)
                        } else {
                            ContentUnavailableView(
                                "Profile unavailable",
                                systemImage: "person.crop.circle.badge.exclamationmark",
                                description: Text("Close this sheet and try again.")
                            )
                        }
                    }
                }
            }
            .alert(
                "Delete \(pendingDelete?.firstName ?? "this child")?",
                isPresented: pendingDeleteBinding
            ) {
                Button("Delete", role: .destructive, action: deletePendingChild)
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            } message: {
                Text("Their measurements and diary entries will also be deleted from this iPhone.")
            }
        }
        .alert("Couldn’t delete child", isPresented: deleteErrorBinding) {
            Button("OK", role: .cancel) { deleteError = nil }
        } message: {
            Text(deleteError ?? "Nothing was deleted. Try again.")
        }
    }

    private var pendingDeleteBinding: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )
    }

    private var deleteErrorBinding: Binding<Bool> {
        Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )
    }

    private func childRow(_ child: Child) -> some View {
        Button {
            editorTarget = .existing(child.id)
        } label: {
            HStack {
                ChildAvatarView(photoJPEG: child.photoJPEG, firstName: child.firstName, size: 48)
                VStack(alignment: .leading) {
                    Text(child.firstName)
                        .font(.wastlyBody.weight(.semibold))
                        .foregroundStyle(WastlyTheme.ink)
                    Text(child.dateOfBirth, format: .dateTime.day().month().year())
                        .font(.wastlyCaption)
                        .foregroundStyle(WastlyTheme.muted)
                    if let summary = latestMeasurementSummary(for: child) {
                        Text(summary)
                            .font(.wastlyCaption)
                            .foregroundStyle(WastlyTheme.muted)
                    }
                }
                Spacer()
                VStack(alignment: .trailing) {
                    if child.id == session.selectedChildID {
                        Text("Today")
                            .font(.wastlyCaption.weight(.semibold))
                            .foregroundStyle(WastlyTheme.sage)
                    }
                    HStack(spacing: 4) {
                        Text("Edit")
                        Image(systemName: "chevron.right")
                    }
                    .font(.wastlyCaption)
                    .foregroundStyle(WastlyTheme.muted)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Edit \(child.firstName)’s profile")
        .accessibilityHint("Includes their photo and measurement history")
    }

    private func latestMeasurementSummary(for child: Child) -> String? {
        guard let latest = child.measurements.max(by: { $0.recordedAt < $1.recordedAt }) else {
            return nil
        }
        let height = latest.heightCentimetres.map { "\(formatted($0)) cm" }
        let weight = latest.weightKilograms.map { "\(formatted($0)) kg" }
        return [height, weight].compactMap { $0 }.joined(separator: " · ")
    }

    private func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    private func didSave(_ child: Child) {
        session.selectedChildID = child.id
        editorTarget = nil
    }

    private func deletePendingChild() {
        guard let child = pendingDelete else { return }
        let deletedID = child.id
        let replacementID = children.first(where: { $0.id != deletedID })?.id
        do {
            try ChildProfileStore.delete(child, in: context)
            if session.selectedChildID == deletedID {
                session.selectedChildID = replacementID
            }
            pendingDelete = nil
        } catch {
            pendingDelete = nil
            deleteError = "Nothing was deleted. Check available storage and try again."
        }
    }
}

private enum ChildEditorTarget: Identifiable {
    case new
    case existing(UUID)

    var id: String {
        switch self {
        case .new: "new"
        case .existing(let id): id.uuidString
        }
    }
}
