import SwiftData
import SwiftUI
import WastlyKit

struct KidsView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var session: SessionStore
    @Query(sort: \Child.createdAt) private var children: [Child]
    @State private var name = ""
    @State private var dob = Calendar.current.date(byAdding: .year, value: -4, to: .now) ?? .now
    @State private var pendingDelete: Child?

    var body: some View {
        NavigationStack {
            List {
                Section("Add a child") {
                    TextField("First name", text: $name)
                    DatePicker("Date of birth", selection: $dob, displayedComponents: .date)
                    Button("Save child") { add() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Section("Children") {
                    ForEach(children, id: \.id) { child in
                        Button {
                            session.selectedChildID = child.id
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(child.firstName)
                                        .font(.wastlyBody)
                                        .foregroundStyle(WastlyTheme.ink)
                                    Text(child.dateOfBirth, format: .dateTime.day().month().year())
                                        .font(.wastlyCaption)
                                        .foregroundStyle(WastlyTheme.muted)
                                }
                                Spacer()
                                if child.id == session.selectedChildID {
                                    Text("Today")
                                        .font(.wastlyCaption)
                                        .foregroundStyle(WastlyTheme.sage)
                                }
                            }
                        }
                        .swipeActions {
                            Button("Delete", role: .destructive) { pendingDelete = child }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Kids")
            .alert("Delete \(pendingDelete?.firstName ?? "this child")?", isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            )) {
                Button("Delete", role: .destructive) {
                    if let child = pendingDelete {
                        context.delete(child)
                        try? context.save()
                        if session.selectedChildID == child.id {
                            session.selectedChildID = children.first(where: { $0.id != child.id })?.id
                        }
                    }
                    pendingDelete = nil
                }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            } message: {
                Text("Their diary rows go with them.")
            }
        }
    }

    private func add() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let child = Child(firstName: trimmed, dateOfBirth: dob)
        context.insert(child)
        try? context.save()
        name = ""
        if children.count + 1 > 0 {
            session.selectedChildID = child.id
        }
    }
}
