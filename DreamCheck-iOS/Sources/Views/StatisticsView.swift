import Foundation
import SwiftUI

struct StatisticsView: View {
    @EnvironmentObject var model: AppModel

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日 EEE"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter
    }()

    var body: some View {
        NavigationView {
            List {
                Section("今天") {
                    row(key: model.todayKey, title: "今天", isToday: true)
                }

                Section("最近 7 天") {
                    ForEach(recentKeys, id: \.self) { key in
                        row(key: key, title: title(for: key), isToday: false)
                    }
                }
            }
            .navigationTitle("统计")
        }
        .navigationViewStyle(.stack)
    }

    private var recentKeys: [String] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (1...7).map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            return ReminderEvent.localDateKey(from: date, calendar: calendar)
        }
    }

    private func title(for key: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Calendar.current.timeZone
        guard let date = formatter.date(from: key) else { return key }
        return Self.dayFormatter.string(from: date)
    }

    private func row(key: String, title: String, isToday: Bool) -> some View {
        let stats = model.statistics(for: key)
        return HStack {
            Text(title)
                .font(isToday ? .headline : .body)
            Spacer()
            Text("完成 \(stats.success) · 忽略 \(stats.ignored)")
                .foregroundColor(.secondary)
            if stats.total > 0 {
                Text(String(format: "%.0f%%", stats.successRate * 100))
                    .frame(minWidth: 44, alignment: .trailing)
            } else {
                Text("—")
                    .frame(minWidth: 44, alignment: .trailing)
                    .foregroundColor(.secondary)
            }
        }
    }
}
