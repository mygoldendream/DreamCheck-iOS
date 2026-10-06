import Foundation
import Combine
import UIKit
import UserNotifications

final class AppModel: ObservableObject {
    @Published var settings: ReminderSettings
    @Published var events: [ReminderEvent]
    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published var nextScheduledAt: Date?

    let notificationManager = NotificationManager()

    private let calculator = ScheduleCalculator()
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let settings = "dreamcheck.settings.v1"
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
        if notificationID.hasPrefix("test-") {
            let now = Date()
            mutateEvents { list in
                list.append(ReminderEvent(
                    id: notificationID,
                    scheduledAt: now,
                    localDateKey: ReminderEvent.localDateKey(from: now),
                    messageIndex: 0,
                    status: action == NotificationManager.actionDone ? .success : .ignored,
                    resolution: .button
                ))
            }
            return
        }

        mutateEvents { list in
            guard let index = list.firstIndex(where: { $0.id == notificationID }) else { return }
            list[index].status = action == NotificationManager.actionDone ? .success : .ignored
            list[index].resolution = action == NotificationManager.actionPause ? .paused : .button
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
