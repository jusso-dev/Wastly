import SwiftData
import SwiftUI
import WastlyKit

struct TodayView: View {
    @Binding var showingLog: Bool
    @EnvironmentObject private var session: SessionStore
    @Query(sort: \Child.createdAt) private var children: [Child]
    @Query private var settingsRows: [AppSettings]
    @Query(sort: \FoodLog.loggedAt, order: .reverse) private var allLogs: [FoodLog]

    private var unit: EnergyUnit {
        settingsRows.first?.energyUnit ?? .kilojoules
    }

    private var child: Child? {
        children.first(where: { $0.id == session.selectedChildID }) ?? children.first
    }

    private var dayLogs: [FoodLog] {
        guard let child else { return [] }
        return DayLogs.filtered(
            logs: ChildSelection.logs(for: child.id, from: allLogs),
            day: session.diaryDay,
            filter: .all
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    dateScroller
                    totalsCard
                    addLogButton
                    ForEach(MealSlot.allCases, id: \.self) { slot in
                        mealSection(slot)
                    }
                }
                .padding(20)
            }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { ChildSwitcher() }
            }
        }
    }

    private var addLogButton: some View {
        Button {
            showingLog = true
        } label: {
            Label("Add a food log", systemImage: "plus")
                .font(.wastlyBody.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(WastlyTheme.sage)
        .accessibilityHint("Opens food search and amount controls")
    }

    private var dateScroller: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(-3...3, id: \.self) { offset in
                    let day = Calendar.current.date(byAdding: .day, value: offset, to: .now) ?? .now
                    Button {
                        session.diaryDay = day
                    } label: {
                        VStack(spacing: 4) {
                            Text(day, format: .dateTime.weekday(.abbreviated))
                                .font(.wastlyCaption)
                            Text(day, format: .dateTime.day())
                                .font(.wastlyBody.weight(.semibold))
                                .monospacedDigit()
                        }
                        .foregroundStyle(Calendar.current.isDate(day, inSameDayAs: session.diaryDay) ? WastlyTheme.onAccent : WastlyTheme.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Calendar.current.isDate(day, inSameDayAs: session.diaryDay) ? WastlyTheme.sage : WastlyTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
    }

    private var totalsCard: some View {
        let totals = DiaryDay.totals(for: dayLogs)
        return JournalCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(Energy.display(totals.eatenKilojoules, unit: unit))
                    .font(.wastlyDayTotal)
                    .monospacedDigit()
                    .foregroundStyle(WastlyTheme.ink)
                Text("Eaten \(Int(totals.eatenGrams)) g · Left \(Int(totals.wastedGrams)) g · \(Energy.display(totals.wastedKilojoules, unit: unit)) wasted")
                    .font(.wastlyCaption)
                    .monospacedDigit()
                    .foregroundStyle(WastlyTheme.muted)
            }
        }
    }

    @ViewBuilder
    private func mealSection(_ slot: MealSlot) -> some View {
        let rows = dayLogs.filter { $0.meal == slot }
        VStack(alignment: .leading, spacing: 8) {
            Text(slot.title)
                .font(.wastlyCaption)
                .foregroundStyle(WastlyTheme.muted)
            if rows.isEmpty {
                Text("Nothing logged.")
                    .font(.wastlyBody)
                    .foregroundStyle(WastlyTheme.muted)
            } else {
                ForEach(rows, id: \.id) { log in
                    LogRow(log: log, unit: unit)
                }
            }
        }
    }
}

struct LogRow: View {
    let log: FoodLog
    let unit: EnergyUnit

    var body: some View {
        JournalCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(log.foodName)
                        .font(.wastlyBody.weight(.semibold))
                        .foregroundStyle(WastlyTheme.ink)
                    Spacer()
                    Text(Energy.display(log.eatenKilojoules, unit: unit))
                        .font(.wastlyCaption)
                        .monospacedDigit()
                        .foregroundStyle(WastlyTheme.muted)
                }
                SplitBar(eaten: log.eatenGrams, wasted: log.wastedGrams)
                Text("Ate \(Int(log.eatenGrams)) g · Left \(Int(log.wastedGrams)) g")
                    .font(.wastlyCaption)
                    .monospacedDigit()
                    .foregroundStyle(WastlyTheme.muted)
            }
        }
    }
}

struct SplitBar: View {
    let eaten: Double
    let wasted: Double

    var body: some View {
        GeometryReader { geo in
            let total = max(eaten + wasted, 1)
            HStack(spacing: 2) {
                WastlyTheme.sage.frame(width: geo.size.width * eaten / total)
                WastlyTheme.apricot.frame(width: geo.size.width * wasted / total)
            }
        }
        .frame(height: 8)
        .clipShape(Capsule())
    }
}

extension MealSlot {
    var title: String {
        switch self {
        case .breakfast: "Breakfast"
        case .lunch: "Lunch"
        case .dinner: "Dinner"
        case .snacks: "Snacks"
        case .other: "Other"
        }
    }
}
