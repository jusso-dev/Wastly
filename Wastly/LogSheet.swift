import SwiftData
import SwiftUI
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
    @State private var customName = ""
    @State private var eaten: Double = 30
    @State private var wasted: Double = 0
    @State private var meal: MealSlot = .snacks
    @State private var note = ""
    @State private var barcode = ""
    @State private var searching = false

    private var unit: EnergyUnit { settingsRows.first?.energyUnit ?? .kilojoules }
    private var child: Child? {
        children.first(where: { $0.id == session.selectedChildID }) ?? children.first
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
            }
            Section("Recents") {
                ForEach(recents.prefix(8), id: \.id) { row in
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
                if recents.isEmpty {
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
                Button {
                    let name = customName.isEmpty ? (query.isEmpty ? "Custom food" : query) : customName
                    pick(FoodHit(id: "custom:\(name)", name: name, kilojoulesPer100g: 0, origin: .custom))
                } label: {
                    Label("Save a custom food", systemImage: "plus.circle")
                }
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
            Section(hit.name) {
                if let brand = hit.brand, !brand.isEmpty {
                    Text(brand).font(.wastlyCaption)
                }
                Text("\(Energy.display(hit.kilojoulesPer100g, unit: unit)) per 100 g")
                    .font(.wastlyCaption)
                    .monospacedDigit()
            }
            Section("How much") {
                stepper("Eaten, grams", value: $eaten)
                stepper("Left, grams", value: $wasted)
                Button("They ate it all") { wasted = 0 }
                Button("None eaten") { eaten = 0 }
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

    private func runSearch() async {
        searching = true
        let result = await session.directory.search(query, online: true)
        hits = result.hits
        miss = result.miss
        searching = false
    }

    private func runBarcode() async {
        let result = await session.directory.barcode(barcode, online: true)
        hits = result.hits
        miss = result.miss
        if let first = result.hits.first { pick(first) }
    }

    private func save(_ hit: FoodHit) {
        guard let child else { return }
        let log = FoodLog(
            meal: meal,
            foodName: hit.name,
            brand: hit.brand,
            barcodeRaw: hit.barcodeRaw,
            eatenGrams: eaten,
            wastedGrams: wasted,
            offeredGrams: eaten + wasted,
            kilojoulesPer100g: hit.kilojoulesPer100g,
            note: note.isEmpty ? nil : note,
            origin: hit.origin,
            child: child
        )
        context.insert(log)
        try? context.save()
        Task {
            await session.directory.remember(hit)
            if hit.origin == .custom {
                await session.directory.saveCustom(hit)
            }
        }
        dismiss()
    }
}
