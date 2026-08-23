import AVFoundation
import SwiftUI
import VisionKit

@MainActor
enum BarcodeScannerSupport {
    static var isSupported: Bool {
        DataScannerViewController.isSupported
    }

    static var isAvailable: Bool {
        DataScannerViewController.isAvailable
    }

    static func requestCameraAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            true
        case .notDetermined:
            await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            false
        @unknown default:
            false
        }
    }
}

struct BarcodeScannerView: View {
    @Environment(\.dismiss) private var dismiss
    let onScanned: (String) -> Void
    let onFailure: (String) -> Void

    var body: some View {
        BarcodeScannerController(
            onScanned: { code in
                onScanned(code)
                dismiss()
            },
            onFailure: { message in
                onFailure(message)
                dismiss()
            }
        )
        .ignoresSafeArea()
        .overlay(alignment: .topTrailing) {
            Button("Close") { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(WastlyTheme.sage)
                .padding()
        }
        .safeAreaInset(edge: .bottom) {
            Text("Hold the retail barcode inside the highlighted area.")
                .font(.wastlyBody)
                .padding()
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial)
        }
    }
}

private struct BarcodeScannerController: UIViewControllerRepresentable {
    let onScanned: (String) -> Void
    let onFailure: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [
                .barcode(symbologies: [.ean8, .ean13, .upce, .code128, .itf14])
            ],
            qualityLevel: .fast,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        Task { @MainActor [weak scanner, weak coordinator = context.coordinator] in
            guard let scanner else { return }
            do {
                try scanner.startScanning()
            } catch {
                coordinator?.fail("The camera scanner couldn’t start. Enter the barcode instead.")
            }
        }
        return scanner
    }

    func updateUIViewController(
        _ controller: DataScannerViewController,
        context: Context
    ) {
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    static func dismantleUIViewController(
        _ controller: DataScannerViewController,
        coordinator: Coordinator
    ) {
        controller.stopScanning()
    }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var parent: BarcodeScannerController
        private var deliveredResult = false

        init(parent: BarcodeScannerController) {
            self.parent = parent
        }

        func dataScanner(
            _ scanner: DataScannerViewController,
            didTapOn item: RecognizedItem
        ) {
            deliver(item, from: scanner)
        }

        func dataScanner(
            _ scanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            guard let barcode = addedItems.first(where: {
                if case .barcode = $0 { return true }
                return false
            }) else { return }
            deliver(barcode, from: scanner)
        }

        func dataScannerDidChangeUnavailabilityReasons(
            _ scanner: DataScannerViewController
        ) {
            guard !DataScannerViewController.isAvailable else { return }
            scanner.stopScanning()
            fail("Camera scanning became unavailable. Enter the barcode instead.")
        }

        func fail(_ message: String) {
            guard !deliveredResult else { return }
            deliveredResult = true
            parent.onFailure(message)
        }

        private func deliver(
            _ item: RecognizedItem,
            from scanner: DataScannerViewController
        ) {
            guard !deliveredResult,
                  case .barcode(let barcode) = item,
                  let payload = barcode.payloadStringValue,
                  !payload.isEmpty
            else {
                return
            }
            deliveredResult = true
            scanner.stopScanning()
            parent.onScanned(payload)
        }
    }
}
