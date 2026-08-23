import SwiftData
import SwiftUI
import WastlyKit

struct FactsView: View {
    @EnvironmentObject private var session: SessionStore
    @Query(sort: \Child.createdAt) private var children: [Child]
    @Query private var settingsRows: [AppSettings]
    @Query(sort: \FoodLog.loggedAt) private var allLogs: [FoodLog]

    private var unit: EnergyUnit { settingsRows.first?.energyUnit ?? .kilojoules }
    private var child: Child? {
        children.first(where: { $0.id == session.selectedChildID }) ?? children.first
    }

    private var childLogs: [FoodLog] {
        guard let child else { return [] }
        return ChildSelection.logs(for: child.id, from: allLogs)
    }

    private var weekLogs: [FoodLog] {
        let start = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: .now)) ?? .now
        return childLogs.filter { $0.loggedAt >= start }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    let totals = FactTotals.from(logs: childLogs)
                    JournalCard {
                        Text(FactTemplates.fact(for: totals, firstName: child?.firstName))
                            .font(.wastlyBody)
                            .foregroundStyle(WastlyTheme.ink)
                    }
                    weekChart
                    JournalCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("All time")
                                .font(.wastlyCaption)
                                .foregroundStyle(WastlyTheme.muted)
                            Text("Eaten \(Int(totals.eatenGrams)) g · \(Energy.display(totals.eatenKilojoules, unit: unit))")
                                .font(.wastlyBody)
                                .monospacedDigit()
                            Text("Left \(Int(totals.wastedGrams)) g · \(Energy.display(totals.wastedKilojoules, unit: unit))")
                                .font(.wastlyBody)
                                .monospacedDigit()
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("Facts")
            .toolbar { ToolbarItem(placement: .topBarLeading) { ChildSwitcher() } }
        }
    }

    private var weekChart: some View {
        let days = (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0 - 6, to: Calendar.current.startOfDay(for: .now)) }
        let hasLogs = days.contains { day in
            !DayLogs.filtered(logs: weekLogs, day: day, filter: .all).isEmpty
        }
        return JournalCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("This week")
                    .font(.wastlyCaption)
                    .foregroundStyle(WastlyTheme.muted)
                if !hasLogs {
                    Text("No logs this week.")
                        .font(.wastlyBody)
                        .foregroundStyle(WastlyTheme.muted)
                } else {
                    HStack(alignment: .bottom, spacing: 8) {
                        ForEach(days, id: \.self) { day in
                            let t = DayLogs.totals(logs: DayLogs.filtered(logs: weekLogs, day: day, filter: .all))
                            let maxG = max(days.map { d in
                                let x = DayLogs.totals(logs: DayLogs.filtered(logs: weekLogs, day: d, filter: .all))
                                return x.eatenG + x.wastedG
                            }.max() ?? 1, 1)
                            VStack(spacing: 4) {
                                HStack(alignment: .bottom, spacing: 2) {
                                    WastlyTheme.sage.frame(width: 8, height: max(4, 80 * t.eatenG / maxG))
                                    WastlyTheme.apricot.frame(width: 8, height: max(4, 80 * t.wastedG / maxG))
                                }
                                Text(day, format: .dateTime.weekday(.narrow))
                                    .font(.wastlyCaption)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    Text("Sage is eaten. Apricot is left.")
                        .font(.wastlyCaption)
                        .foregroundStyle(WastlyTheme.muted)
                }
            }
        }
    }
}
