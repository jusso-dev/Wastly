import SwiftData
import SwiftUI
import WastlyKit

struct DiaryView: View {
    @EnvironmentObject private var session: SessionStore
    @Query(sort: \Child.createdAt) private var children: [Child]
    @Query private var settingsRows: [AppSettings]
    @Query(sort: \FoodLog.loggedAt, order: .reverse) private var allLogs: [FoodLog]
    @State private var calendarMode: DiaryCalendarMode = .week

    private var unit: EnergyUnit { settingsRows.first?.energyUnit ?? .kilojoules }
    private var child: Child? {
        children.first(where: { $0.id == session.selectedChildID }) ?? children.first
    }

    private var childLogs: [FoodLog] {
        guard let child else { return [] }
        return ChildSelection.logs(for: child.id, from: allLogs)
    }

    private var rows: [FoodLog] {
        DiaryDay.filtered(
            childLogs,
            on: session.diaryDay,
            filter: session.diaryFilter
        )
    }

    private var calendarDays: [DiaryCalendarDay] {
        DiaryCalendar.days(containing: session.diaryDay, mode: calendarMode)
    }

    private var weekdaySymbols: [String] {
        let calendar = Calendar.current
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        guard symbols.count == 7 else { return symbols }
        let start = max(0, min(6, calendar.firstWeekday - 1))
        return (0..<7).map { symbols[(start + $0) % 7] }
    }

    private var calendarTitle: String {
        if calendarMode == .month {
            return session.diaryDay.formatted(.dateTime.month(.wide).year())
        }
        guard let first = calendarDays.first?.date,
              let last = calendarDays.last?.date
        else { return "Selected week" }
        return "\(first.formatted(.dateTime.day().month(.abbreviated))) – \(last.formatted(.dateTime.day().month(.abbreviated).year()))"
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                calendarCard
                Picker("Filter", selection: $session.diaryFilter) {
                    ForEach(DiaryLogFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                List {
                    if rows.isEmpty {
                        Text("No matching logs for this day.")
                            .font(.wastlyBody)
                            .foregroundStyle(WastlyTheme.muted)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    } else {
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
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Diary")
            .toolbar { ToolbarItem(placement: .topBarLeading) { ChildSwitcher() } }
        }
    }

    private var calendarCard: some View {
        JournalCard {
            VStack(spacing: 10) {
                Picker("Calendar view", selection: $calendarMode) {
                    ForEach(DiaryCalendarMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    Button {
                        moveCalendar(by: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .frame(width: 32, height: 32)
                    }
                    .accessibilityLabel("Previous \(calendarMode.title.lowercased())")

                    Spacer()
                    Text(calendarTitle)
                        .font(.wastlyBody.weight(.semibold))
                        .multilineTextAlignment(.center)
                    Spacer()

                    Button {
                        moveCalendar(by: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .frame(width: 32, height: 32)
                    }
                    .accessibilityLabel("Next \(calendarMode.title.lowercased())")
                }

                if calendarMode == .month {
                    LazyVGrid(columns: calendarColumns, spacing: 6) {
                        ForEach(weekdaySymbols.indices, id: \.self) { index in
                            Text(weekdaySymbols[index])
                                .font(.wastlyCaption)
                                .foregroundStyle(WastlyTheme.muted)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }

                LazyVGrid(columns: calendarColumns, spacing: 6) {
                    ForEach(calendarDays) { day in
                        dayButton(day)
                    }
                }

                HStack {
                    DatePicker(
                        "Jump to date",
                        selection: $session.diaryDay,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.compact)
                    Spacer()
                    Button("Today") {
                        session.diaryDay = .now
                    }
                }
                .font(.wastlyCaption)
            }
        }
        .padding(.horizontal, 20)
    }

    private var calendarColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    }

    private func dayButton(_ day: DiaryCalendarDay) -> some View {
        let selected = Calendar.current.isDate(day.date, inSameDayAs: session.diaryDay)
        let hasLogs = childLogs.contains {
            Calendar.current.isDate($0.loggedAt, inSameDayAs: day.date)
        }
        return Button {
            session.diaryDay = day.date
        } label: {
            VStack(spacing: 3) {
                if calendarMode == .week {
                    Text(day.date, format: .dateTime.weekday(.narrow))
                        .font(.wastlyCaption)
                }
                Text(day.date, format: .dateTime.day())
                    .font(.wastlyBody.weight(.semibold))
                    .monospacedDigit()
                Circle()
                    .fill(selected ? WastlyTheme.onAccent : WastlyTheme.apricot)
                    .frame(width: 4, height: 4)
                    .opacity(hasLogs ? 1 : 0)
            }
            .frame(maxWidth: .infinity, minHeight: 42)
            .foregroundStyle(
                selected
                    ? WastlyTheme.onAccent
                    : day.isInDisplayedMonth ? WastlyTheme.ink : WastlyTheme.muted
            )
            .background(selected ? WastlyTheme.sage : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.date.formatted(date: .complete, time: .omitted))
        .accessibilityValue(hasLogs ? "Has logs" : "No logs")
    }

    private func moveCalendar(by offset: Int) {
        session.diaryDay = DiaryCalendar.movedDate(
            from: session.diaryDay,
            by: offset,
            mode: calendarMode
        )
    }
}
