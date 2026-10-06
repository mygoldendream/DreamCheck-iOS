import Foundation
import Combine
import UIKit
import UserNotifications

final class AppModel: ObservableObject {
    @Published var settings: ReminderSettings
    @Published var events: [ReminderEvent]
    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published var nextScheduledAt: Date?
    @Published var recordTarget: RecordTarget?

    let notificationManager = NotificationManager.shared

    private let calculator = ScheduleCalculator()
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let settings = "dreamcheck.settings.v2"
        static let events = "dreamcheck.events.v1"
    }

    init() {
        if let data = defaults.data(forKey: Keys.settings),
           let decoded = try? JSONDecoder().decode(ReminderSettings.self, from: data) {
            settings = decoded.validated()
        } else {
            settings = ReminderSettings()
        }

        if let data = defaults.data(forKey: Keys.events),
           let decoded = try? JSONDecoder().decode([ReminderEvent].self, from: data) {
            events = decoded
        } else {
            events = []
        }

        notificationManager.onAction = { [weak self] action, identifier in
            self?.handle(action: action, notificationID: identifier)
        }

        refreshAuthorizationStatus()
    }

    // MARK: - Today / statistics

    var todayKey: String { ReminderEvent.localDateKey(from: Date()) }

    var todayEvents: [ReminderEvent] {
        events.filter { $0.localDateKey == todayKey }
    }

    var dailyStatistics: DailyStatistics {
        let todays = todayEvents
        return DailyStatistics(
            success: todays.filter { $0.status == .success }.count,
            ignored: todays.filter { $0.status == .ignored }.count
        )
    }

    func statistics(for key: String) -> DailyStatistics {
        let subset = events.filter { $0.localDateKey == key }
        return DailyStatistics(
            success: subset.filter { $0.status == .success }.count,
            ignored: subset.filter { $0.status == .ignored }.count
        )
    }

    func events(on key: String) -> [ReminderEvent] {
        events.filter { $0.localDateKey == key }.sorted { $0.scheduledAt < $1.scheduledAt }
    }

    func event(id: String) -> ReminderEvent? {
        events.first { $0.id == id }
    }

    func message(for event: ReminderEvent) -> ReminderMessage? {
        guard event.messageIndex >= 0, event.messageIndex < ReminderMessages.all.count else { return nil }
        return ReminderMessages.all[event.messageIndex]
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        refreshAuthorizationStatus()
    }

    func refreshAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.authorizationStatus = settings.authorizationStatus
            }
        }
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    // MARK: - Settings mutation

    func updateSettings(_ mutate: (inout ReminderSettings) -> Void) {
        var updated = settings
        mutate(&updated)
        settings = updated.validated()
        persistSettings()
        refreshSchedule()
    }

    // MARK: - Scheduling

    func refreshSchedule() {
        reconcile()
        guard settings.enabled else {
            notificationManager.replaceAll(with: [])
            nextScheduledAt = nil
            return
        }

        let batch = calculator.makeBatch(settings: settings, now: Date(), limit: 60)
        notificationManager.replaceAll(with: batch.reminders)

        // Drop stale future pending events (from a previous schedule), then add the new batch.
        mutateEvents { list in
            list.removeAll { $0.status == .pending && $0.scheduledAt > Date() }
            let existing = Set(list.map { $0.id })
            for reminder in batch.reminders where !existing.contains(reminder.id) {
                list.append(ReminderEvent(
                    id: reminder.id,
                    scheduledAt: reminder.date,
                    localDateKey: ReminderEvent.localDateKey(from: reminder.date),
                    messageIndex: reminder.messageIndex,
                    status: .pending,
                    resolution: nil
                ))
            }
        }

        nextScheduledAt = batch.reminders.first?.date

        if batch.settings != settings {
            settings = batch.settings
            persistSettings()
        }
    }

    func fireTestReminder() {
        notificationManager.fireTestReminder()
    }

    // MARK: - Resolution

    private func handle(action: String, notificationID: String) {
        ensureEventExists(id: notificationID)
        switch action {
        case NotificationManager.actionDone:
            resolve(notificationID, status: .success, resolution: .button)
        case NotificationManager.actionRecord:
            recordTarget = RecordTarget(id: notificationID)
        case NotificationManager.actionSkip:
            resolve(notificationID, status: .ignored, resolution: .skipped)
        default:
            break
        }
    }

    private func resolve(_ id: String, status: ReminderStatus, resolution: Resolution) {
        mutateEvents { list in
            guard let index = list.firstIndex(where: { $0.id == id }) else { return }
            list[index].status = status
            list[index].resolution = resolution
        }
    }

    private func ensureEventExists(id: String) {
        guard !events.contains(where: { $0.id == id }) else { return }
        let now = Date()
        mutateEvents { list in
            list.append(ReminderEvent(
                id: id,
                scheduledAt: now,
                localDateKey: ReminderEvent.localDateKey(from: now),
                messageIndex: 0,
                status: .pending,
                resolution: nil
            ))
        }
    }

    // MARK: - Records

    func openRecord(for event: ReminderEvent) {
        recordTarget = RecordTarget(id: event.id)
    }

    /// 记录一次验梦并标记为完成。
    func saveRecord(eventID: String, note: String) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        mutateEvents { list in
            guard let index = list.firstIndex(where: { $0.id == eventID }) else { return }
            list[index].note = trimmed.isEmpty ? nil : trimmed
            list[index].status = .success
            list[index].resolution = .button
        }
    }

    /// 只保存备注，不改变完成状态。
    func updateNote(eventID: String, note: String) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        mutateEvents { list in
            guard let index = list.firstIndex(where: { $0.id == eventID }) else { return }
            list[index].note = trimmed.isEmpty ? nil : trimmed
        }
    }

    /// 跳过这一次提醒。
    func skipRecord(eventID: String) {
        mutateEvents { list in
            guard let index = list.firstIndex(where: { $0.id == eventID }) else { return }
            list[index].status = .ignored
            list[index].resolution = .skipped
        }
    }

    // MARK: - Segments

    func setUseSegments(_ on: Bool) {
        updateSettings { settings in
            settings.useSegments = on
            if on && settings.segments.isEmpty {
                settings.segments = [
                    ScheduleSegment(startMinutes: 9 * 60, endExclusiveMinutes: 12 * 60, intervalMinutes: 15),
                    ScheduleSegment(startMinutes: 12 * 60, endExclusiveMinutes: 18 * 60, intervalMinutes: 30),
                    ScheduleSegment(startMinutes: 18 * 60, endExclusiveMinutes: 22 * 60, intervalMinutes: 20),
                ]
            }
        }
    }

    func addSegment() {
        updateSettings { settings in
            settings.segments.append(ScheduleSegment(
                startMinutes: settings.window.startMinutes,
                endExclusiveMinutes: settings.window.endExclusiveMinutes,
                intervalMinutes: settings.intervalMinutes
            ))
        }
    }

    func deleteSegments(at offsets: IndexSet) {
        updateSettings { settings in
            let removing = offsets.compactMap { $0 < settings.segments.count ? settings.segments[$0].id : nil }
            settings.segments.removeAll { removing.contains($0.id) }
        }
    }

    func updateSegment(id: String, _ mutate: (inout ScheduleSegment) -> Void) {
        updateSettings { settings in
            guard let index = settings.segments.firstIndex(where: { $0.id == id }) else { return }
            mutate(&settings.segments[index])
        }
    }

    private func reconcile() {
        let cutoff = Date().addingTimeInterval(-60)
        mutateEvents { list in
            for index in list.indices where list[index].status == .pending && list[index].scheduledAt < cutoff {
                list[index].status = .ignored
                list[index].resolution = .timeout
            }
        }
    }

    // MARK: - Persistence

    private func mutateEvents(_ mutate: (inout [ReminderEvent]) -> Void) {
        var copy = events
        mutate(&copy)
        events = copy
        persistEvents()
    }

    private func persistSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: Keys.settings)
        }
    }

    private func persistEvents() {
        if let data = try? JSONEncoder().encode(events) {
            defaults.set(data, forKey: Keys.events)
        }
    }
}
