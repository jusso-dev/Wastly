import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import WastlyKit

struct LogSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var session: SessionStore
    @Query(sort: \Child.createdAt) private var children: [Child]
    @Query(sort: \FoodCache.lastUsedAt, order: .reverse) private var recents: [FoodCache]
    @Query private var settingsRows: [AppSettings]

    @State private var query = ""
    @State private var hits: [FoodHit] = []
    @State private var miss: FoodLookupMiss?
    @State private var selected: FoodHit?
    @State private var labelScan: NutritionLabelScan?
    @State private var scannedFoodName = ""
    @State private var scannedEnergyPer100g = ""
    @State private var scannedServingGrams = ""
    @State private var selectedLabelPhoto: PhotosPickerItem?
    @State private var customName = ""
    @State private var customEnergyPer100g = ""
    @State private var eaten: Double = 30
    @State private var wasted: Double = 0
    @State private var meal: MealSlot = .snacks
    @State private var note = ""
    @State private var barcode = ""
    @State private var searching = false
    @State private var readingLabel = false
    @State private var showingScanner = false
    @State private var showingLabelCamera = false
    @State private var errorMessage: String?

    private var unit: EnergyUnit { settingsRows.first?.energyUnit ?? .kilojoules }
    private var child: Child? {
        children.first(where: { $0.id == session.selectedChildID }) ?? children.first
    }
    private var recentFoods: [FoodCache] {
        recents
            .filter { $0.useCount > 0 }
            .sorted { lhs, rhs in
                if lhs.useCount != rhs.useCount { return lhs.useCount > rhs.useCount }
                return lhs.lastUsedAt > rhs.lastUsedAt
            }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let selected {
                    confirm(selected)
                } else {
                    search
                }
            }
            .background(WastlyTheme.paper)
            .navigationTitle(selected == nil ? "Add" : "Confirm")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .tint(WastlyTheme.sage)
        .task { await runSearch() }
        .task(id: selectedLabelPhoto) {
            await loadSelectedLabelPhoto()
        }
        .fullScreenCover(isPresented: $showingScanner) {
            BarcodeScannerView(
                onScanned: { scanned in
                    barcode = scanned
                    Task { await runBarcode() }
                },
                onFailure: { errorMessage = $0 }
            )
        }
        .fullScreenCover(isPresented: $showingLabelCamera) {
            LabelCameraPicker(
                onImage: { data in
                    showingLabelCamera = false
                    Task { await readLabel(data) }
                },
                onCancel: { showingLabelCamera = false }
            )
            .ignoresSafeArea()
        }
        .interactiveDismissDisabled(readingLabel)
        .alert("Couldn’t add food", isPresented: errorBinding) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Nothing was saved. Try again.")
        }
    }

    private var search: some View {
        List {
            Section {
                TextField("Search food", text: $query)
                    .textInputAutocapitalization(.never)
                    .onSubmit { Task { await runSearch() } }
                HStack {
                    TextField("Barcode", text: $barcode)
                        .keyboardType(.numberPad)
                    Button("Match") { Task { await runBarcode() } }
                }
                Button {
                    Task { await openScanner() }
                } label: {
                    Label("Scan barcode with camera", systemImage: "barcode.viewfinder")
                }
            }
            Section("Read a pack label") {
                Button {
                    Task { await openLabelCamera() }
                } label: {
                    Label("Take label photo", systemImage: "camera")
                }
                PhotosPicker(selection: $selectedLabelPhoto, matching: .images) {
                    Label("Choose label photo", systemImage: "photo.on.rectangle")
                }
                if readingLabel {
                    ProgressView("Reading on this device…")
                        .font(.wastlyCaption)
                }
                Text("Vision runs offline. The photo is processed in memory and is not stored or uploaded.")
                    .font(.wastlyCaption)
                    .foregroundStyle(WastlyTheme.muted)
            }
            Section("Recents") {
                ForEach(recentFoods.prefix(8), id: \.id) { row in
                    Button {
                        pick(FoodHit(
                            id: row.providerKey ?? row.id.uuidString,
                            name: row.name,
                            brand: row.brand,
                            barcodeRaw: row.barcodeRaw,
                            kilojoulesPer100g: row.kilojoulesPer100g,
                            servingGrams: row.servingGrams,
                            origin: FoodOrigin(rawValue: row.originRaw) ?? .recent
                        ))
                    } label: {
                        hitLabel(name: row.name, brand: row.brand, kJ: row.kilojoulesPer100g)
                    }
                }
                if recentFoods.isEmpty {
                    Text("No recents yet.")
                        .font(.wastlyCaption)
                        .foregroundStyle(WastlyTheme.muted)
                }
            }
            Section("Results") {
                if searching {
                    Text("Looking up…")
                        .font(.wastlyCaption)
                        .foregroundStyle(WastlyTheme.muted)
                }
                ForEach(hits) { hit in
                    Button { pick(hit) } label: {
                        hitLabel(name: hit.name, brand: hit.brand, kJ: hit.kilojoulesPer100g)
                    }
                }
                if let miss {
                    Text(missCopy(miss))
                        .font(.wastlyCaption)
                        .foregroundStyle(WastlyTheme.muted)
                }
            }
            Section("Custom food") {
                TextField("Custom food name", text: $customName)
                TextField(customEnergyPrompt, text: $customEnergyPer100g)
                    .keyboardType(.decimalPad)
                Text("Optional. Leave blank to log grams without energy totals.")
                    .font(.wastlyCaption)
                    .foregroundStyle(WastlyTheme.muted)
                Button(action: pickCustomFood) {
                    Label("Use custom food", systemImage: "plus.circle")
                }
                .disabled(customFoodName == nil)
            }
        }
        .scrollContentBackground(.hidden)
        .background(WastlyTheme.paper)
        .onChange(of: query) { _, _ in
            Task { await runSearch() }
        }
    }

    private func confirm(_ hit: FoodHit) -> some View {
        Form {
            if let labelScan {
                scannedLabelSection(labelScan)
            } else {
                Section(hit.name) {
                    if let brand = hit.brand, !brand.isEmpty {
                        Text(brand).font(.wastlyCaption)
                    }
                    if hit.origin == .custom, hit.kilojoulesPer100g == 0 {
                        Text("No energy entered · grams will still be saved")
                            .font(.wastlyCaption)
                    } else {
                        Text("\(Energy.display(hit.kilojoulesPer100g, unit: unit)) per 100 g")
                            .font(.wastlyCaption)
                            .monospacedDigit()
                    }
                }
            }
            Section("How much") {
                stepper("Eaten, grams", value: $eaten)
                stepper("Left, grams", value: $wasted)
                Button("They ate it all", action: ateAll)
                Button("None eaten", action: noneEaten)
            }
            Section("Meal") {
                Picker("Meal", selection: $meal) {
                    ForEach(MealSlot.allCases, id: \.self) { slot in
                        Text(slot.title).tag(slot)
                    }
                }
                TextField("Note (optional)", text: $note)
            }
            Button { save(hit) } label: {
                Label("Save log", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(WastlyTheme.sage)
        }
        .scrollContentBackground(.hidden)
        .background(WastlyTheme.paper)
    }

    private func scannedLabelSection(_ scan: NutritionLabelScan) -> some View {
        Section("Review label") {
            TextField("Food name", text: $scannedFoodName)
                .textInputAutocapitalization(.words)
            TextField(scannedEnergyPrompt, text: $scannedEnergyPer100g)
                .keyboardType(.decimalPad)
            TextField("Serving grams (optional)", text: $scannedServingGrams)
                .keyboardType(.decimalPad)
            Label(
                "On-device read · \(scan.confidence.formatted(.percent.precision(.fractionLength(0)))) confidence",
                systemImage: "text.viewfinder"
            )
            .font(.wastlyCaption)
            .foregroundStyle(WastlyTheme.muted)
            DisclosureGroup("Recognized text") {
                Text(scan.lines.isEmpty ? "No text recognized." : scan.lines.map(\.text).joined(separator: "\n"))
                    .font(.wastlyCaption)
                    .textSelection(.enabled)
            }
            Button("Wrong read? Search instead", action: rejectLabelRead)
        }
    }

    private func stepper(_ title: String, value: Binding<Double>) -> some View {
        Stepper(value: value, in: 0...2000, step: 5) {
            Text("\(title): \(Int(value.wrappedValue))")
                .monospacedDigit()
        }
    }

    private func hitLabel(name: String, brand: String?, kJ: Double) -> some View {
        VStack(alignment: .leading) {
            Text(name).font(.wastlyBody).foregroundStyle(WastlyTheme.ink)
            Text("\(brand.map { "\($0) · " } ?? "")\(Energy.display(kJ, unit: unit)) / 100 g")
                .font(.wastlyCaption)
                .monospacedDigit()
                .foregroundStyle(WastlyTheme.muted)
        }
    }

    private var customFoodName: String? {
        let custom = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty { return custom }
        let searched = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return searched.isEmpty ? nil : searched
    }

    private var customEnergyPrompt: String {
        unit == .kilojoules ? "kJ per 100 g (optional)" : "kcal per 100 g (optional)"
    }

    private var scannedEnergyPrompt: String {
        unit == .kilojoules ? "Editable kJ per 100 g" : "Editable kcal per 100 g"
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func missCopy(_ miss: FoodLookupMiss) -> String {
        switch miss {
        case .offline: "No signal. Use a recent or save a custom food."
        case .unknownBarcode: "No exact barcode match. Do not guess. Save a custom food."
        case .emptyQuery: "Type a name or a barcode."
        }
    }

    private func pick(_ hit: FoodHit) {
        selected = hit
        if let serving = hit.servingGrams, serving > 0 {
            eaten = serving
        }
    }

    private func pickCustomFood() {
        guard let name = customFoodName else { return }
        do {
            pick(try CustomFoodBuilder.make(
                name: name,
                energyPer100gText: customEnergyPer100g,
                unit: unit
            ))
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Check the custom food details and try again."
        }
    }

    private func ateAll() {
        let amounts = LogAmountShortcut.ateAll(eaten: eaten, wasted: wasted)
        eaten = amounts.eaten
        wasted = amounts.wasted
    }

    private func noneEaten() {
        let amounts = LogAmountShortcut.noneEaten(eaten: eaten, wasted: wasted)
        eaten = amounts.eaten
        wasted = amounts.wasted
    }

    private func runSearch() async {
        searching = true
        let result = await session.directory.search(query, online: true)
        hits = result.hits
        miss = result.miss
        searching = false
    }

    private func runBarcode() async {
        searching = true
        defer { searching = false }
        let result = await session.directory.barcode(barcode, online: true)
        hits = result.hits
        miss = result.miss
        if let first = result.hits.first { pick(first) }
    }

    private func openScanner() async {
        guard BarcodeScannerSupport.isSupported else {
            errorMessage = "Camera barcode scanning isn’t available on this device. Enter the barcode instead."
            return
        }
        guard await BarcodeScannerSupport.requestCameraAccess() else {
            errorMessage = "Camera access is off. Allow it in Settings, or enter the barcode instead."
            return
        }
        guard BarcodeScannerSupport.isAvailable else {
            errorMessage = "Camera barcode scanning is temporarily unavailable. Enter the barcode instead."
            return
        }
        showingScanner = true
    }

    private func openLabelCamera() async {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            errorMessage = "A camera isn’t available here. Choose a label photo instead."
            return
        }
        guard await BarcodeScannerSupport.requestCameraAccess() else {
            errorMessage = "Camera access is off. Allow it in Settings, or choose a label photo instead."
            return
        }
        showingLabelCamera = true
    }

    private func loadSelectedLabelPhoto() async {
        guard let selectedLabelPhoto else { return }
        do {
            guard let data = try await selectedLabelPhoto.loadTransferable(type: Data.self) else {
                throw NutritionLabelOCRError.unreadableImage
            }
            await readLabel(data)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "That label photo couldn’t be opened. Choose another photo and try again."
        }
    }

    private func readLabel(_ imageData: Data) async {
        readingLabel = true
        defer { readingLabel = false }
        do {
            let scan = try await session.labelOCR.recognize(imageData: imageData)
            labelScan = scan
            let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            scannedFoodName = trimmedQuery.isEmpty ? "Scanned food" : trimmedQuery
            if let energy = scan.energyKilojoulesPer100g {
                let displayed = unit == .kilojoules
                    ? energy
                    : Energy.kilocalories(fromKilojoules: energy)
                scannedEnergyPer100g = editableNumber(displayed)
            } else {
                scannedEnergyPer100g = ""
            }
            scannedServingGrams = scan.servingGrams.map(editableNumber) ?? ""
            pick(FoodHit(
                id: "ocr:label",
                name: scannedFoodName,
                kilojoulesPer100g: scan.energyKilojoulesPer100g ?? 0,
                servingGrams: scan.servingGrams,
                origin: .custom
            ))
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "That label couldn’t be read. Try a brighter, straighter photo."
        }
    }

    private func rejectLabelRead() {
        let suggestion = scannedFoodName == "Scanned food" ? "" : scannedFoodName
        labelScan = nil
        selected = nil
        query = suggestion
    }

    private func editableNumber(_ value: Double) -> String {
        if value.rounded() == value, value <= Double(Int.max) {
            return String(Int(value))
        }
        return String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private func save(_ hit: FoodHit) {
        guard let child else {
            errorMessage = "Choose a child before saving this log."
            return
        }
        do {
            let resolvedHit = try resolvedHitForSave(hit)
            try FoodLogWriter.save(
                FoodLogDraft(
                    hit: resolvedHit,
                    loggedAt: session.diaryDay,
                    meal: meal,
                    eatenGrams: eaten,
                    wastedGrams: wasted,
                    note: note
                ),
                for: child,
                in: context
            )
            Task {
                await session.directory.remember(resolvedHit)
                if resolvedHit.origin == .custom {
                    await session.directory.saveCustom(resolvedHit)
                }
            }
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Nothing was saved. Check available storage and try again."
        }
    }

    private func resolvedHitForSave(_ hit: FoodHit) throws -> FoodHit {
        guard labelScan != nil else { return hit }
        return try CustomFoodBuilder.make(
            name: scannedFoodName,
            energyPer100gText: scannedEnergyPer100g,
            unit: unit,
            servingGramsText: scannedServingGrams
        )
    }
}
