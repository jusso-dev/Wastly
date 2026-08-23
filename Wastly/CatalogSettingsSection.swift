import Foundation
import SwiftUI

struct CatalogSettingsSection: View {
    @EnvironmentObject private var session: SessionStore
    @State private var showingClearConfirmation = false

    var body: some View {
        Section("Catalog") {
            if let updatedAt = session.catalogSnapshot.lastSuccessAt {
                Text(
                    "Last catalog update "
                        + updatedAt.formatted(date: .abbreviated, time: .shortened)
                )
            } else {
                Text("Using the bundled offline seed.")
            }
            LabeledContent("Version", value: session.catalogSnapshot.version.formatted())
            LabeledContent("Offline foods", value: session.catalogSnapshot.rowCount.formatted())
            LabeledContent("Estimated catalog size", value: catalogSizeLabel)
                .font(.wastlyCaption)

            if session.catalogIsRunning {
                updatingControls
            } else {
                updateButton
            }

            if !session.catalogIsConfigured {
                Text(
                    "No catalog endpoint is configured in this build. "
                        + "Seed foods and local-first live lookup still work."
                )
                .font(.wastlyCaption)
                .foregroundStyle(WastlyTheme.muted)
            }

            Button("Clear downloaded catalog", role: .destructive) {
                showingClearConfirmation = true
            }
            .disabled(session.catalogIsRunning)
            .accessibilityIdentifier("settings.clearCatalog")
            Text("The bundled seed, custom foods, and diary logs are never removed.")
                .font(.wastlyCaption)

            statusMessage
        }
        .confirmationDialog(
            "Clear downloaded catalog?",
            isPresented: $showingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear downloaded catalog", role: .destructive) {
                Task { await session.clearCatalog() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Downloaded catalog and lookup rows will be removed. "
                    + "The bundled seed, custom foods, and diary logs stay on this iPhone."
            )
        }
    }

    private var updatingControls: some View {
        Group {
            HStack {
                ProgressView()
                Text("Updating in the background…")
            }
            Button("Cancel catalog update", role: .cancel) {
                session.cancelCatalogUpdate()
            }
            .accessibilityIdentifier("settings.cancelCatalogUpdate")
        }
    }

    private var updateButton: some View {
        Button {
            session.updateCatalog()
        } label: {
            Label("Update catalog", systemImage: "arrow.triangle.2.circlepath")
        }
        .disabled(!session.catalogIsConfigured)
        .accessibilityIdentifier("settings.updateCatalog")
    }

    @ViewBuilder private var statusMessage: some View {
        if let error = session.catalogSnapshot.lastError,
           session.catalogMessage == nil {
            Text("Last update failed. \(error)")
                .font(.wastlyCaption)
                .foregroundStyle(WastlyTheme.muted)
                .accessibilityIdentifier("settings.catalogError")
        }
        if let message = session.catalogMessage {
            Text(message)
                .font(.wastlyCaption)
                .foregroundStyle(WastlyTheme.muted)
                .accessibilityIdentifier("settings.catalogMessage")
        }
    }

    private var catalogSizeLabel: String {
        ByteCountFormatter.string(
            fromByteCount: Int64(session.catalogSnapshot.estimatedBytes),
            countStyle: .file
        )
    }
}
