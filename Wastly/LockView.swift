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
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(WastlyTheme.sage)
                .accessibilityHidden(true)
            Button {
                Task { await session.unlock() }
            } label: {
                if session.authenticationIsRunning {
                    ProgressView()
                        .frame(minWidth: 180)
                } else {
                    Text("Unlock with Face ID or Passcode")
                }
            }
            .font(.wastlyBody.weight(.semibold))
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(WastlyTheme.sage)
            .foregroundStyle(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .disabled(session.authenticationIsRunning)
            .accessibilityIdentifier("lock.unlock")
            if let message = session.lockMessage {
                Text(message)
                    .font(.wastlyCaption)
                    .foregroundStyle(WastlyTheme.muted)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("lock.message")
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .accessibilityIdentifier("lock.screen")
    }
}
