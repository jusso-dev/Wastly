import SwiftData
import SwiftUI
import WastlyKit

struct DiaryView: View {
    @EnvironmentObject private var session: SessionStore
    @Query(sort: \Child.createdAt) private var children: [Child]
    @Query private var settingsRows: [AppSettings]
    @Query(sort: \FoodLog.loggedAt, order: .reverse) private var allLogs: [FoodLog]

    private var unit: EnergyUnit { settingsRows.first?.energyUnit ?? .kilojoules }
    private var child: Child? {
        children.first(where: { $0.id == session.selectedChildID }) ?? children.first
    }

    private var rows: [FoodLog] {
        guard let child else { return [] }
        return DayLogs.filtered(logs: allLogs.filter { $0.child?.id == child.id }, day: session.diaryDay, filter: session.diaryFilter)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                DatePicker("Day", selection: $session.diaryDay, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .padding(.horizontal, 20)
                Picker("Filter", selection: $session.diaryFilter) {
                    ForEach(SessionStore.DiaryFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                List {
                    ForEach(MealSlot.allCases, id: \.self) { slot in
                        let mealRows = rows.filter { $0.meal == slot }
                        if !mealRows.isEmpty {
                            Section(slot.title) {
                                ForEach(mealRows, id: \.id) { log in
                                    LogRow(log: log, unit: unit)
                                        .listRowBackground(Color.clear)
                                        .listRowSeparator(.hidden)
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Diary")
            .toolbar { ToolbarItem(placement: .topBarLeading) { ChildSwitcher() } }
        }
    }
}

enum DiaryFilterLogic {
    static func include(_ log: FoodLog, filter: SessionStore.DiaryFilter) -> Bool {
        switch filter {
        case .all: true
        case .eaten: log.eatenGrams > 0
        case .wasted: log.wastedGrams > 0
        }
    }
}
