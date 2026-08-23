import SwiftUI

struct LockView: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("Wastly")
                .font(.wastlyDayTotal)
                .foregroundStyle(WastlyTheme.ink)
            Text("The diary is locked.")
                .font(.wastlyBody)
                .foregroundStyle(WastlyTheme.muted)
            Button("Unlock") {
                Task { await session.unlock() }
            }
            .font(.wastlyBody.weight(.semibold))
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(WastlyTheme.sage)
            .foregroundStyle(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .task { await session.unlock() }
    }
}
