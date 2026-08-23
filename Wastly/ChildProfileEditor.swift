import ImageIO
import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import WastlyKit

struct ChildProfileEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let child: Child?
    let onSaved: (Child) -> Void
    @State private var name: String
    @State private var dateOfBirth: Date
    @State private var photoJPEG: Data?
    @State private var heightText = ""
    @State private var weightText = ""
    @State private var measurementDate = Date.now
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isLoadingPhoto = false
    @State private var errorMessage: String?

    init(child: Child?, onSaved: @escaping (Child) -> Void) {
        self.child = child
        self.onSaved = onSaved
        _name = State(initialValue: child?.firstName ?? "")
        _dateOfBirth = State(
            initialValue: child?.dateOfBirth
                ?? Calendar.current.date(byAdding: .year, value: -4, to: .now)
                ?? .now
        )
        _photoJPEG = State(initialValue: child?.photoJPEG)
    }

    var body: some View {
        Form {
            photoSection
            detailsSection
            measurementSection
            measurementHistorySection
        }
        .navigationTitle(child == nil ? "New child" : "Edit child")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoadingPhoto)
            }
        }
        .interactiveDismissDisabled(isLoadingPhoto)
        .task(id: selectedPhoto) {
            await loadSelectedPhoto()
        }
        .alert("Couldn’t save profile", isPresented: errorBinding) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Nothing was saved. Try again.")
        }
    }

    private var photoSection: some View {
        let pickerTitle = photoJPEG == nil ? "Choose photo" : "Change photo"
        return Section {
            HStack {
                ChildAvatarView(photoJPEG: photoJPEG, firstName: name, size: 72)
                VStack(alignment: .leading) {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label(pickerTitle, systemImage: "photo.on.rectangle")
                    }
                    if isLoadingPhoto {
                        ProgressView("Preparing photo")
                            .font(.wastlyCaption)
                    }
                    if photoJPEG != nil {
                        Button("Remove photo", role: .destructive) {
                            photoJPEG = nil
                            selectedPhoto = nil
                        }
                    }
                }
            }
        } header: {
            Text("Photo (optional)")
        } footer: {
            Text("A small copy stays in this child’s profile on this iPhone.")
        }
    }

    private var detailsSection: some View {
        Section("Profile") {
            TextField("First name", text: $name)
                .textContentType(.givenName)
                .autocorrectionDisabled()
            DatePicker(
                "Date of birth",
                selection: $dateOfBirth,
                in: ...Date.now,
                displayedComponents: .date
            )
        }
    }

    private var measurementSection: some View {
        Section {
            TextField("Height in cm", text: $heightText)
                .keyboardType(.decimalPad)
            TextField("Weight in kg", text: $weightText)
                .keyboardType(.decimalPad)
            DatePicker("Recorded", selection: $measurementDate, in: ...Date.now, displayedComponents: .date)
        } header: {
            Text(child == nil ? "First measurement (optional)" : "Add measurement (optional)")
        } footer: {
            Text("Leave both fields blank to save without adding a measurement.")
        }
    }

    @ViewBuilder
    private var measurementHistorySection: some View {
        if let child {
            Section("Measurement history") {
                let measurements = child.measurements.sorted { $0.recordedAt > $1.recordedAt }
                if measurements.isEmpty {
                    Text("No measurements yet.")
                        .foregroundStyle(WastlyTheme.muted)
                } else {
                    ForEach(measurements, id: \.id) { measurement in
                        measurementRow(measurement)
                    }
                }
            }
        }
    }

    private func measurementRow(_ measurement: MeasurementPoint) -> some View {
        HStack {
            Text(measurement.recordedAt, format: .dateTime.day().month().year())
                .font(.wastlyCaption)
                .foregroundStyle(WastlyTheme.muted)
            Spacer()
            Text(measurementSummary(measurement))
                .font(.wastlyBody)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private func measurementSummary(_ measurement: MeasurementPoint) -> String {
        let height = measurement.heightCentimetres.map { "\(formatted($0)) cm" }
        let weight = measurement.weightKilograms.map { "\(formatted($0)) kg" }
        return [height, weight].compactMap { $0 }.joined(separator: " · ")
    }

    private func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func save() {
        do {
            let measurement = try parsedMeasurement()
            let input = ChildProfileInput(
                firstName: name,
                dateOfBirth: dateOfBirth,
                photoJPEG: photoJPEG
            )
            let savedChild: Child
            if let child {
                try ChildProfileStore.update(
                    child,
                    with: input,
                    newMeasurement: measurement,
                    in: context
                )
                savedChild = child
            } else {
                savedChild = try ChildProfileStore.create(
                    input,
                    initialMeasurement: measurement,
                    in: context
                )
            }
            onSaved(savedChild)
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Nothing was saved. Check available storage and try again."
        }
    }

    private func parsedMeasurement() throws -> ChildMeasurementInput? {
        let heightValue = heightText.trimmingCharacters(in: .whitespacesAndNewlines)
        let weightValue = weightText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !heightValue.isEmpty || !weightValue.isEmpty else { return nil }

        let height = heightValue.isEmpty ? nil : Double(heightValue)
        let weight = weightValue.isEmpty ? nil : Double(weightValue)
        guard (heightValue.isEmpty || height != nil), (weightValue.isEmpty || weight != nil) else {
            throw ChildProfileError.invalidMeasurement
        }
        return ChildMeasurementInput(
            recordedAt: measurementDate,
            heightCentimetres: height,
            weightKilograms: weight
        )
    }

    private func loadSelectedPhoto() async {
        guard let selectedPhoto else { return }
        isLoadingPhoto = true
        defer { isLoadingPhoto = false }

        do {
            guard let original = try await selectedPhoto.loadTransferable(type: Data.self) else {
                throw ProfilePhotoError.unreadable
            }
            let thumbnail = await Task.detached(priority: .userInitiated) {
                ProfilePhotoRenderer.thumbnailJPEG(from: original)
            }.value
            guard let thumbnail else { throw ProfilePhotoError.unreadable }
            photoJPEG = thumbnail
        } catch {
            errorMessage = "That photo couldn’t be prepared. Choose another photo and try again."
        }
    }
}

struct ChildAvatarView: View {
    let photoJPEG: Data?
    let firstName: String
    let size: CGFloat

    var body: some View {
        Group {
            if let photoJPEG,
               let image = ProfilePhotoRenderer.image(from: photoJPEG, maxPixelSize: Int(size * 3))
            {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(WastlyTheme.sage.opacity(0.18))
                    .overlay {
                        Text(initial)
                            .font(.wastlyBody.weight(.semibold))
                            .foregroundStyle(WastlyTheme.sage)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var initial: String {
        firstName.trimmingCharacters(in: .whitespacesAndNewlines)
            .first
            .map(String.init)?
            .uppercased() ?? "?"
    }
}

private enum ProfilePhotoError: Error {
    case unreadable
}

private enum ProfilePhotoRenderer {
    static func thumbnailJPEG(from data: Data) -> Data? {
        image(from: data, maxPixelSize: 768)?.jpegData(compressionQuality: 0.82)
    }

    static func image(from data: Data, maxPixelSize: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: image)
    }
}
