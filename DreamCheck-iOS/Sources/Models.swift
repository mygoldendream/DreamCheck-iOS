import Foundation

enum ReminderMode: String, Codable, CaseIterable, Identifiable {
    case aligned
    case continuous

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .aligned: return "整点对齐"
        case .continuous: return "连续间隔"
        }
    }

    var intervalChoices: [Int] {
        switch self {
        case .aligned:
            return [1, 2, 3, 4, 5, 6, 10, 12, 15, 20, 30, 60, 70, 80, 90, 100, 110, 120]
        case .continuous:
            return Array(1...120)
        }
    }

    func supports(_ minutes: Int) -> Bool { intervalChoices.contains(minutes) }

    func normalize(_ minutes: Int) -> Int {
        let safe = min(max(minutes, 1), 120)
        return intervalChoices.min { lhs, rhs in
            let dl = abs(lhs - safe)
            let dr = abs(rhs - safe)
            return dl < dr || (dl == dr && lhs < rhs)
        } ?? safe
    }
}

enum VibrationIntensity: String, Codable, CaseIterable, Identifiable {
    case light
    case medium
    case strong

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .light: return "轻"
        case .medium: return "中"
        case .strong: return "强"
        }
    }
}

struct TimeWindow: Codable, Equatable {
    var startMinutes: Int
    var endExclusiveMinutes: Int

    var crossesMidnight: Bool { startMinutes > endExclusiveMinutes }

    init(startMinutes: Int, endExclusiveMinutes: Int) {
        self.startMinutes = startMinutes
        self.endExclusiveMinutes = endExclusiveMinutes
    }
}

struct ScheduleSegment: Codable, Identifiable, Equatable {
    var id: String
    var startMinutes: Int
    var endExclusiveMinutes: Int
    var intervalMinutes: Int
    var enabled: Bool

    var crossesMidnight: Bool { startMinutes > endExclusiveMinutes }

    init(id: String = UUID().uuidString,
         startMinutes: Int,
         endExclusiveMinutes: Int,
         intervalMinutes: Int,
         enabled: Bool = true) {
        self.id = id
        self.startMinutes = startMinutes
        self.endExclusiveMinutes = endExclusiveMinutes
        self.intervalMinutes = intervalMinutes
        self.enabled = enabled
    }
}

struct RecordTarget: Identifiable, Equatable {
    let id: String
}

struct ReminderSettings: Codable, Equatable {
    var enabled: Bool = false
    var window: TimeWindow = TimeWindow(startMinutes: 9 * 60, endExclusiveMinutes: 22 * 60)
    var reminderMode: ReminderMode = .aligned
    var intervalMinutes: Int = 15
    var alignmentAnchorEpochMillis: Int64?
    var lastMessageIndex: Int?
    var vibrationIntensity: VibrationIntensity = .medium
    var useSegments: Bool = false
    var segments: [ScheduleSegment] = []

    func validated() -> ReminderSettings {
        var copy = self
        copy.intervalMinutes = min(max(copy.intervalMinutes, 1), 120)
        if !copy.reminderMode.supports(copy.intervalMinutes) {
            copy.intervalMinutes = copy.reminderMode.normalize(copy.intervalMinutes)
        }
        copy.window.startMinutes = min(max(copy.window.startMinutes, 0), 1439)
        copy.window.endExclusiveMinutes = min(max(copy.window.endExclusiveMinutes, 0), 1439)
        if copy.window.startMinutes == copy.window.endExclusiveMinutes {
            copy.window.endExclusiveMinutes = (copy.window.startMinutes + 1) % 1440
        }
        if !(copy.reminderMode == .aligned && copy.intervalMinutes > 60) {
            copy.alignmentAnchorEpochMillis = nil
        }
        if let index = copy.lastMessageIndex, !ReminderMessages.all.indices.contains(index) {
            copy.lastMessageIndex = nil
        }
        copy.segments = copy.segments.map { segment in
            var fixed = segment
            fixed.startMinutes = min(max(fixed.startMinutes, 0), 1439)
            fixed.endExclusiveMinutes = min(max(fixed.endExclusiveMinutes, 0), 1439)
            if fixed.startMinutes == fixed.endExclusiveMinutes {
                fixed.endExclusiveMinutes = (fixed.startMinutes + 1) % 1440
            }
            fixed.intervalMinutes = min(max(fixed.intervalMinutes, 1), 120)
            return fixed
        }
        return copy
    }
}

enum ReminderStatus: String, Codable {
    case pending
    case success
    case ignored
}

enum Resolution: String, Codable {
    case button
    case swipe
    case timeout
    case paused
    case skipped
}

struct ReminderEvent: Codable, Identifiable, Equatable {
    var id: String
    var scheduledAt: Date
    var localDateKey: String
    var messageIndex: Int
    var status: ReminderStatus
    var resolution: Resolution?
    var note: String? = nil

    static func localDateKey(from date: Date, calendar: Calendar = .current) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
    }
}

struct DailyStatistics {
    let success: Int
    let ignored: Int

    var total: Int { success + ignored }
    var successRate: Double { total == 0 ? 0 : Double(success) / Double(total) }
}
