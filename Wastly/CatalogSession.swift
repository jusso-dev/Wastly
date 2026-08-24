import Foundation
import WastlyKit

extension SessionStore {
    static func configuredCatalogURL() -> URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "CatalogURL") as? String else {
            return nil
        }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              !value.contains("$("),
              let url = URL(string: value),
              let host = url.host,
              PrivacyAllowlist.isAllowedCatalogURL(url, extraHosts: [host])
        else { return nil }
        return url
    }

    var catalogIsConfigured: Bool { catalogSync != nil && catalogEndpoint != nil }

    func bootstrapCatalog() async {
        do {
            try await store.insertSeedIfEmpty()
        } catch {
            catalogMessage = "Wastly couldn’t prepare its bundled offline catalogue."
        }
        catalogSnapshot = await store.catalogSnapshot()
        if catalogIsConfigured {
            updateCatalog(showMessage: false)
        }
    }

    func updateCatalog(showMessage: Bool = true) {
        guard catalogUpdateTask == nil else { return }
        guard let catalogSync, let catalogEndpoint else {
            if showMessage {
                catalogMessage = "No catalog endpoint is configured in this build. "
                    + "The bundled offline catalogue remains available."
            }
            return
        }

        catalogIsRunning = true
        if showMessage { catalogMessage = nil }
        catalogUpdateTask = Task { [weak self] in
            guard let self else { return }
            defer {
                catalogIsRunning = false
                catalogUpdateTask = nil
            }
            do {
                let result = try await catalogSync.pull(from: catalogEndpoint)
                catalogSnapshot = result.snapshot
                if showMessage {
                    catalogMessage = message(for: result)
                }
            } catch is CancellationError {
                catalogSnapshot = await store.catalogSnapshot()
                if showMessage {
                    catalogMessage = "Catalog update cancelled. The previous version is still available."
                }
            } catch {
                catalogSnapshot = await store.catalogSnapshot()
                if showMessage {
                    catalogMessage = "Catalog update failed. The previous version is still available. "
                        + error.localizedDescription
                }
            }
        }
    }

    func cancelCatalogUpdate() {
        catalogUpdateTask?.cancel()
    }

    func clearCatalog() async {
        let runningTask = catalogUpdateTask
        runningTask?.cancel()
        await runningTask?.value
        do {
            let result = try await store.clearDownloadedCatalogLeavingSeedCustomAndLogs()
            catalogSnapshot = result.snapshot
            catalogMessage = clearMessage(
                removed: result.downloadedRows + result.lookupCacheRows
            )
        } catch {
            catalogSnapshot = await store.catalogSnapshot()
            catalogMessage = "Wastly couldn’t clear downloaded catalog data. "
                + "Check available storage and try again."
        }
    }

    private func message(for result: CatalogSyncResult) -> String {
        if result.status == .notModified {
            return "Catalog is already up to date."
        }
        return "Updated to catalog version \(result.snapshot.version) with "
            + "\(result.snapshot.rowCount.formatted()) offline foods."
    }

    private func clearMessage(removed: Int) -> String {
        if removed == 1 {
            return "Removed 1 downloaded food. The bundled catalogue, custom foods, and diary remain."
        }
        return "Removed \(removed.formatted()) downloaded foods. "
            + "The bundled catalogue, custom foods, and diary remain."
    }
}
