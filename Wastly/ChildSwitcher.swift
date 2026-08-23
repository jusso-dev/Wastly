import SwiftData
import SwiftUI
import WastlyKit

struct ChildSwitcher: View {
    @EnvironmentObject private var session: SessionStore
    @Query(sort: \Child.createdAt) private var children: [Child]

    var body: some View {
        if children.count > 1 {
            Menu {
                ForEach(children, id: \.id) { child in
                    Button(child.firstName) {
                        session.selectedChildID = child.id
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(currentName)
                        .font(.wastlyBody)
                        .foregroundStyle(WastlyTheme.ink)
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundStyle(WastlyTheme.muted)
                }
            }
            .accessibilityLabel("Switch child")
        }
    }

    private var currentName: String {
        children.first(where: { $0.id == session.selectedChildID })?.firstName ?? children.first?.firstName ?? "Child"
    }
}
