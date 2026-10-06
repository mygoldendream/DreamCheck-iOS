import Foundation

enum NextSchedule: Equatable {
    case disabled
    case at(Date, alignmentAnchorEpochMillis: Int64?)
}

struct ScheduledReminder {
    let id: String
    let date: Date
    let messageIndex: Int
}

struct ScheduleBatch {
    let reminders: [ScheduledReminder]
    let settings: ReminderSettings
}

struct ScheduleCalculator {
    let calendar: Calendar

    init(timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.calendar = calendar
    }

    private struct WindowOccurrence {
        let start: Date
        let endExclusive: Date
        func contains(_ date: Date) -> Bool { date >= start && date < endExclusive }
    }

    func next(now: Date, settings: ReminderSettings) -> NextSchedule {
        guard settings.enabled else { return .disabled }
        switch settings.reminderMode {
        case .continuous:
            return .at(continuous(now: now, settings: settings), alignmentAnchorEpochMillis: nil)
        case .aligned:
            return aligned(now: now, settings: settings)
        }
    }

    func makeBatch(settings: ReminderSettings, now: Date, limit: Int = 60) -> ScheduleBatch {
        guard settings.enabled else {
            return ScheduleBatch(reminders: [], settings: settings)
        }
        var working = settings
        var reminders: [ScheduledReminder] = []
        var cursor = now
        let horizon = calendar.date(byAdding: .day, value: 14, to: now) ?? now.addingTimeInterval(14 * 86_400)

        loop: while reminders.count < limit {
            switch next(now: cursor, settings: working) {
            case .disabled:
                break loop
            case .at(let date, let anchor):
                if date > horizon { break loop }
                let index = MessageSelector.select(lastMessageIndex: working.lastMessageIndex)
                reminders.append(ScheduledReminder(id: "rem-\(UUID().uuidString)", date: date, messageIndex: index))
                working.lastMessageIndex = index
                if let anchor = anchor {
                    working.alignmentAnchorEpochMillis = anchor
                }
                cursor = date.addingTimeInterval(1)
            }
        }
        return ScheduleBatch(reminders: reminders, settings: working)
    }

    private func continuous(now: Date, settings: ReminderSettings) -> Date {
        let occurrence = currentOccurrence(now: now, window: settings.window)
            ?? nextOccurrence(now: now, window: settings.window)
        let candidate = now.addingTimeInterval(TimeInterval(settings.intervalMinutes * 60))
        if candidate < occurrence.endExclusive {
            return candidate
        } else {
            return nextOccurrenceAfter(occurrence).start
        }
    }

    private func aligned(now: Date, settings: ReminderSettings) -> NextSchedule {
        let current = currentOccurrence(now: now, window: settings.window)
        let occurrence = current ?? nextOccurrence(now: now, window: settings.window)
        let reference = current == nil ? occurrence.start : now
        let inclusive = current == nil

        if let first = alignedWithin(now: now, reference: reference, inclusive: inclusive,
                                     occurrence: occurrence, settings: settings) {
            return first
        }

        let next = nextOccurrenceAfter(occurrence)
        if let second = alignedWithin(now: now, reference: next.start, inclusive: true,
                                      occurrence: next, settings: settings) {
            return second
        }

        let anchor = settings.intervalMinutes > 60
            ? Int64(next.start.timeIntervalSince1970 * 1000)
            : nil
        return .at(next.start, alignmentAnchorEpochMillis: anchor)
    }

    private func alignedWithin(now: Date, reference: Date, inclusive: Bool,
                               occurrence: WindowOccurrence, settings: ReminderSettings) -> NextSchedule? {
        if settings.intervalMinutes <= 60 {
            let candidate = nextClockSlot(reference: reference, intervalMinutes: settings.intervalMinutes,
                                          inclusive: inclusive)
            return occurrence.contains(candidate) ? .at(candidate, alignmentAnchorEpochMillis: nil) : nil
        }

        let storedAnchor: Date? = settings.alignmentAnchorEpochMillis
            .map { Date(timeIntervalSince1970: Double($0) / 1000) }
            .flatMap { anchor in
                guard occurrence.contains(anchor), isExactLocalHour(anchor) else { return nil }
                return anchor
            }
        let anchor = storedAnchor ?? nextClockSlot(reference: reference, intervalMinutes: 60, inclusive: inclusive)
        guard occurrence.contains(anchor) else { return nil }

        let candidate = nextFromAnchor(now: now, anchor: anchor, intervalMinutes: settings.intervalMinutes)
        guard occurrence.contains(candidate) else { return nil }
        return .at(candidate, alignmentAnchorEpochMillis: Int64(anchor.timeIntervalSince1970 * 1000))
    }

    private func nextClockSlot(reference: Date, intervalMinutes: Int, inclusive: Bool) -> Date {
        var comps = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond],
                                             from: reference)
        comps.second = 0
        comps.nanosecond = 0
        var candidate = calendar.date(from: comps) ?? reference
        let minute = comps.minute ?? 0
        let remainder = minute % intervalMinutes
        if remainder != 0 {
            candidate = calendar.date(byAdding: .minute, value: intervalMinutes - remainder, to: candidate) ?? candidate
        }
        let eligible = inclusive ? candidate >= reference : candidate > reference
        if !eligible {
            candidate = calendar.date(byAdding: .minute, value: intervalMinutes, to: candidate) ?? candidate
        }
        return candidate
    }

    private func nextFromAnchor(now: Date, anchor: Date, intervalMinutes: Int) -> Date {
        if now < anchor { return anchor }
        let interval = TimeInterval(intervalMinutes * 60)
        let elapsed = now.timeIntervalSince(anchor)
        let steps = floor(elapsed / interval) + 1
        return anchor.addingTimeInterval(steps * interval)
    }

    private func currentOccurrence(now: Date, window: TimeWindow) -> WindowOccurrence? {
        let time = minutesOfDay(now)
        let contains = window.crossesMidnight
            ? (time >= window.startMinutes || time < window.endExclusiveMinutes)
            : (time >= window.startMinutes && time < window.endExclusiveMinutes)
        guard contains else { return nil }
        let startDate = (window.crossesMidnight && time < window.endExclusiveMinutes)
            ? calendar.date(byAdding: .day, value: -1, to: startOfDay(now)) ?? startOfDay(now)
            : startOfDay(now)
        return occurrence(startDate: startDate, window: window)
    }

    private func nextOccurrence(now: Date, window: TimeWindow) -> WindowOccurrence {
        let time = minutesOfDay(now)
        let startDate: Date
        if window.crossesMidnight {
            startDate = startOfDay(now)
        } else if time < window.startMinutes {
            startDate = startOfDay(now)
        } else {
            startDate = calendar.date(byAdding: .day, value: 1, to: startOfDay(now)) ?? startOfDay(now)
        }
        return occurrence(startDate: startDate, window: window)
    }

    private func nextOccurrenceAfter(_ occurrence: WindowOccurrence) -> WindowOccurrence {
        let start = calendar.date(byAdding: .day, value: 1, to: occurrence.start) ?? occurrence.start
        let end = calendar.date(byAdding: .day, value: 1, to: occurrence.endExclusive) ?? occurrence.endExclusive
        return WindowOccurrence(start: start, endExclusive: end)
    }

    private func occurrence(startDate: Date, window: TimeWindow) -> WindowOccurrence {
        let endDate = window.crossesMidnight
            ? calendar.date(byAdding: .day, value: 1, to: startDate) ?? startDate
            : startDate
        return WindowOccurrence(
            start: date(on: startDate, minutes: window.startMinutes),
            endExclusive: date(on: endDate, minutes: window.endExclusiveMinutes)
        )
    }

    private func date(on day: Date, minutes: Int) -> Date {
        let hour = minutes / 60
        let minute = minutes % 60
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    private func minutesOfDay(_ date: Date) -> Int {
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }

    private func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    private func isExactLocalHour(_ date: Date) -> Bool {
        let comps = calendar.dateComponents([.minute, .second, .nanosecond], from: date)
        return (comps.minute ?? 0) == 0 && (comps.second ?? 0) == 0 && (comps.nanosecond ?? 0) == 0
    }
}
