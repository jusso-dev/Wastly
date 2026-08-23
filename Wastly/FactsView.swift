import SwiftData
import SwiftUI
import WastlyKit

struct FactsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var session: SessionStore
    @Query(sort: \Child.createdAt) private var children: [Child]
    @Query private var settingsRows: [AppSettings]
    @Query(sort: \FoodLog.loggedAt) private var allLogs: [FoodLog]
    @Query private var facts: [FunFact]
    @State private var cacheNotice: String?

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

    private var totals: FactTotals {
        FactTotals.from(logs: childLogs)
    }

    private var cachedFact: FunFact? {
        guard let childID = child?.id else { return nil }
        return facts
            .filter { $0.child?.id == childID }
            .max { $0.createdAt < $1.createdAt }
    }

    private var displayedFact: String {
        if let cachedFact, cachedFact.inputsHash == totals.inputsHash {
            return cachedFact.text
        }
        return FactTemplates.fact(for: totals, firstName: child?.firstName)
    }

    private var refreshID: String {
        let day = Calendar.current.startOfDay(for: .now).timeIntervalSinceReferenceDate
        return "\(child?.id.uuidString ?? "none")|\(Int(day))|\(totals.inputsHash)"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    JournalCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(displayedFact)
                                .font(.wastlyBody)
                                .foregroundStyle(WastlyTheme.ink)
                            if let cacheNotice {
                                Text(cacheNotice)
                                    .font(.wastlyCaption)
                                    .foregroundStyle(WastlyTheme.muted)
                            }
                        }
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
            .task(id: refreshID) { refreshFact() }
        }
    }

    private func refreshFact(now: Date = .now) {
        guard let child else { return }
        let currentTotals = FactTotals.from(logs: childLogs, now: now)
        let previous = cachedFact
        guard FactCachePolicy.shouldRegenerate(
            cachedInputsHash: previous?.inputsHash,
            cachedAt: previous?.createdAt,
            totals: currentTotals,
            now: now
        ) else { return }

        let text = FactTemplates.fact(for: currentTotals, firstName: child.firstName)
        if let previous, Calendar.current.isDate(previous.createdAt, inSameDayAs: now) {
            previous.text = text
            previous.inputsHash = currentTotals.inputsHash
            previous.createdAt = now
        } else {
            modelContext.insert(FunFact(
                text: text,
                inputsHash: currentTotals.inputsHash,
                createdAt: now,
                child: child
            ))
        }

        do {
            try modelContext.save()
            cacheNotice = nil
        } catch {
            cacheNotice = "The fact is available, but its offline cache could not be saved."
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
                            let totals = DiaryDay.totals(
                                for: DayLogs.filtered(logs: weekLogs, day: day, filter: .all)
                            )
                            let maxG = max(days.map { d in
                                let dayTotals = DiaryDay.totals(
                                    for: DayLogs.filtered(logs: weekLogs, day: d, filter: .all)
                                )
                                return dayTotals.eatenGrams + dayTotals.wastedGrams
                            }.max() ?? 1, 1)
                            VStack(spacing: 4) {
                                HStack(alignment: .bottom, spacing: 2) {
                                    WastlyTheme.sage.frame(width: 8, height: max(4, 80 * totals.eatenGrams / maxG))
                                    WastlyTheme.apricot.frame(width: 8, height: max(4, 80 * totals.wastedGrams / maxG))
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
