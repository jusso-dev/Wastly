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

    private var totals: FactTotals {
        FactTotals.from(logs: childLogs)
    }

    private var weekSummary: FactWeekSummary {
        FactWeekSummary.from(logs: childLogs)
    }

    private var cachedFact: FunFact? {
        guard let childID = child?.id else { return nil }
        return facts
            .filter { $0.child?.id == childID }
            .max { $0.createdAt < $1.createdAt }
    }

    private var usesOnlineFacts: Bool {
        (settingsRows.first?.llmEnabled ?? false) && session.factGenerator != nil
    }

    private var cacheInputsHash: String {
        cacheInputsHash(for: totals, usesOnlineFacts: usesOnlineFacts)
    }

    private var displayedFact: String {
        if let cachedFact, cachedFact.inputsHash == cacheInputsHash {
            return cachedFact.text
        }
        return FactTemplates.fact(for: totals, firstName: child?.firstName)
    }

    private var refreshID: String {
        let day = Calendar.current.startOfDay(for: .now).timeIntervalSinceReferenceDate
        return "\(child?.id.uuidString ?? "none")|\(Int(day))|\(cacheInputsHash)"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    JournalCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Latest facts")
                                .font(.wastlyCaption)
                                .foregroundStyle(WastlyTheme.muted)
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
                            Text("\(Energy.display(totals.eatenKilojoules, unit: unit)) eaten · \(Int(totals.eatenGrams)) g")
                                .font(.wastlyBody)
                                .monospacedDigit()
                            Text("\(Energy.display(totals.wastedKilojoules, unit: unit)) left · \(Int(totals.wastedGrams)) g")
                                .font(.wastlyBody)
                                .monospacedDigit()
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("Facts")
            .toolbar { ToolbarItem(placement: .topBarLeading) { ChildSwitcher() } }
            .task(id: refreshID) { await refreshFact() }
        }
    }

    private func refreshFact(now: Date = .now) async {
        guard let child else { return }
        let currentTotals = FactTotals.from(logs: childLogs, now: now)
        let generator = usesOnlineFacts ? session.factGenerator : nil
        let currentInputsHash = cacheInputsHash(
            for: currentTotals,
            usesOnlineFacts: generator != nil
        )
        let previous = cachedFact
        guard FactCachePolicy.shouldRegenerate(
            cachedInputsHash: previous?.inputsHash,
            cachedAt: previous?.createdAt,
            currentInputsHash: currentInputsHash,
            now: now
        ) else { return }

        let template = FactTemplates.fact(for: currentTotals, firstName: child.firstName)
        let fact: FunFact
        if let previous, Calendar.current.isDate(previous.createdAt, inSameDayAs: now) {
            previous.text = template
            previous.inputsHash = currentInputsHash
            previous.createdAt = now
            fact = previous
        } else {
            let created = FunFact(
                text: template,
                inputsHash: currentInputsHash,
                createdAt: now,
                child: child
            )
            modelContext.insert(created)
            fact = created
        }

        do {
            try modelContext.save()
            cacheNotice = nil
        } catch {
            cacheNotice = "The fact is available, but its offline cache could not be saved."
            return
        }

        guard let generator,
              currentTotals.eatenGrams + currentTotals.wastedGrams >= 1
        else { return }
        let result = await FactService.generateOrFallback(
            totals: currentTotals,
            firstName: child.firstName,
            using: generator
        )
        guard !Task.isCancelled else { return }
        guard result.source == .remote else {
            cacheNotice = "Using the offline fact because the optional fact service was unavailable."
            return
        }

        fact.text = result.text
        do {
            try modelContext.save()
            cacheNotice = nil
        } catch {
            cacheNotice = "The fact is available, but its offline cache could not be saved."
        }
    }

    private func cacheInputsHash(
        for totals: FactTotals,
        usesOnlineFacts: Bool
    ) -> String {
        let mode = usesOnlineFacts ? FactPrompt.version : "template-v1"
        return "\(totals.inputsHash)|\(mode)"
    }

    private var weekChart: some View {
        let summary = weekSummary
        return JournalCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("This week")
                    .font(.wastlyCaption)
                    .foregroundStyle(WastlyTheme.muted)
                if !summary.hasLogs {
                    Text("No logs this week.")
                        .font(.wastlyBody)
                        .foregroundStyle(WastlyTheme.muted)
                } else {
                    HStack(alignment: .bottom, spacing: 8) {
                        ForEach(summary.days) { day in
                            VStack(spacing: 4) {
                                HStack(alignment: .bottom, spacing: 2) {
                                    WastlyTheme.sage.frame(
                                        width: 8,
                                        height: summary.barHeight(for: day.eatenGrams)
                                    )
                                    WastlyTheme.apricot.frame(
                                        width: 8,
                                        height: summary.barHeight(for: day.wastedGrams)
                                    )
                                }
                                Text(day.day, format: .dateTime.weekday(.narrow))
                                    .font(.wastlyCaption)
                            }
                            .frame(maxWidth: .infinity)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(day.day.formatted(.dateTime.weekday(.wide)))
                            .accessibilityValue(
                                "Eaten \(Int(day.eatenGrams)) grams, left \(Int(day.wastedGrams)) grams"
                            )
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
