import Foundation
import SwiftUI

struct StatisticsView: View {
    @EnvironmentObject var model: AppModel
    @State private var monthAnchor: Date = Date()

    private var calendar: Calendar { Calendar.current }

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter
    }()

    private static let monthKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    var body: some View {
        NavigationView {
            List {
                Section {
                    monthHeader
                    weekdayHeader
                    calendarGrid
                }

                Section("本月汇总") {
                    let stats = monthStatistics
                    summaryRow("完成次数", "\(stats.success)")
                    summaryRow("跳过 / 忽略", "\(stats.ignored)")
                    summaryRow("总提醒数", "\(stats.total)")
                    summaryRow("验梦率", stats.total == 0 ? "—" : String(format: "%.0f%%", stats.successRate * 100))
                }

                Section {
                    Text("点某一天可以看当天的次数、验梦率和每一条记录。圆圈颜色越绿表示那天完成得越好。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("统计")
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - Header

    private var monthHeader: some View {
        HStack {
            Button {
                shiftMonth(-1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)

            Spacer()

            Text(Self.monthFormatter.string(from: monthAnchor))
                .font(.headline)

            Spacer()

            Button {
                shiftMonth(1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }

    private var weekdayHeader: some View {
        LazyVGrid(columns: gridColumns, spacing: 4) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var calendarGrid: some View {
        LazyVGrid(columns: gridColumns, spacing: 6) {
            ForEach(monthCells.indices, id: \.self) { index in
                if let date = monthCells[index] {
                    dayCell(date)
                } else {
                    Color.clear.frame(height: 44)
                }
            }
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let key = ReminderEvent.localDateKey(from: date, calendar: calendar)
        let stats = model.statistics(for: key)
        let isToday = key == model.todayKey
        return NavigationLink(destination: DayDetailView(dateKey: key)) {
            VStack(spacing: 3) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.footnote)
                    .fontWeight(isToday ? .bold : .regular)
                    .foregroundColor(isToday ? Color.accentColor : Color.primary)
                Circle()
                    .fill(dotColor(stats))
                    .frame(width: 6, height: 6)
            }
            .frame(maxWidth: .infinity, minHeight: 42)
        }
    }

    // MARK: - Helpers

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
    }

    private var weekdaySymbols: [String] {
        ["一", "二", "三", "四", "五", "六", "日"]
    }

    private var monthCells: [Date?] {
        let start = startOfMonth(monthAnchor)
        let weekday = calendar.component(.weekday, from: start) // 1 = 周日
        let leading = (weekday + 5) % 7
        let dayCount = calendar.range(of: .day, in: .month, for: start)?.count ?? 30

        var cells: [Date?] = Array(repeating: nil, count: leading)
        for offset in 0..<dayCount {
            cells.append(calendar.date(byAdding: .day, value: offset, to: start))
        }
        while cells.count % 7 != 0 {
            cells.append(nil)
        }
        return cells
    }

    private var monthKey: String {
        Self.monthKeyFormatter.string(from: monthAnchor)
    }

    private var monthStatistics: DailyStatistics {
        let subset = model.events.filter { $0.localDateKey.hasPrefix(monthKey) }
        return DailyStatistics(
            success: subset.filter { $0.status == .success }.count,
            ignored: subset.filter { $0.status == .ignored }.count
        )
    }

    private func summaryRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundColor(.secondary)
        }
    }

    private func dotColor(_ stats: DailyStatistics) -> Color {
        guard stats.total > 0 else { return Color.secondary.opacity(0.15) }
        if stats.successRate >= 0.6 { return .green }
        if stats.successRate >= 0.3 { return .orange }
        return .red
    }

    private func startOfMonth(_ date: Date) -> Date {
        let comps = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: comps) ?? date
    }

    private func shiftMonth(_ delta: Int) {
        if let moved = calendar.date(byAdding: .month, value: delta, to: startOfMonth(monthAnchor)) {
            monthAnchor = moved
        }
    }
}

struct DayDetailView: View {
    @EnvironmentObject var model: AppModel
    let dateKey: String

    private static let titleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日 EEEE"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter
    }()

    private static let parseFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private var dayEvents: [ReminderEvent] {
        model.events(on: dateKey)
    }

    var body: some View {
        List {
            Section("概览") {
                let stats = model.statistics(for: dateKey)
                row("完成次数", "\(stats.success)")
                row("跳过 / 忽略", "\(stats.ignored)")
                row("总提醒数", "\(stats.total)")
                row("验梦率", stats.total == 0 ? "—" : String(format: "%.0f%%", stats.successRate * 100))
            }

            Section("记录") {
                if dayEvents.isEmpty {
                    Text("这一天没有记录")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(dayEvents) { event in
                        Button {
                            model.openRecord(for: event)
                        } label: {
                            recordRow(event)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var title: String {
        guard let date = Self.parseFormatter.date(from: dateKey) else { return dateKey }
        return Self.titleFormatter.string(from: date)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundColor(.secondary)
        }
    }

    private func recordRow(_ event: ReminderEvent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(Self.timeFormatter.string(from: event.scheduledAt))
                    .font(.subheadline)
                    .bold()
                statusBadge(event.status)
                Spacer()
                Image(systemName: "square.and.pencil")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if let message = model.message(for: event) {
                Text(message.title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if let note = event.note, !note.isEmpty {
                Text(note)
                    .font(.footnote)
            }
        }
        .padding(.vertical, 2)
    }

    private func statusBadge(_ status: ReminderStatus) -> some View {
        let text: String
        let color: Color
        switch status {
        case .success:
            text = "完成"
            color = .green
        case .ignored:
            text = "跳过"
            color = .orange
        case .pending:
            text = "待处理"
            color = .gray
        }
        return Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .cornerRadius(6)
    }
}
