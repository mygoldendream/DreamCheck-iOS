import Foundation
import UserNotifications

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let categoryIdentifier = "REMINDER"
    static let actionDone = "DONE"
    static let actionIgnore = "IGNORE"
    static let actionPause = "PAUSE"

    var onAction: ((String, String) -> Void)?

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        registerCategory()
    }

    private func registerCategory() {
        let done = UNNotificationAction(identifier: Self.actionDone, title: "完成了", options: [])
        let ignore = UNNotificationAction(identifier: Self.actionIgnore, title: "忽略", options: [])
        let pause = UNNotificationAction(identifier: Self.actionPause, title: "暂停", options: [.foreground])
        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [done, ignore, pause],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    func replaceAll(with reminders: [ScheduledReminder]) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        for reminder in reminders {
            let message = ReminderMessages.all[reminder.messageIndex]
            let content = UNMutableNotificationContent()
            content.title = message.title
            content.body = message.body
            content.sound = .default
            content.categoryIdentifier = Self.categoryIdentifier
            content.userInfo = ["messageIndex": reminder.messageIndex]
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second],
                                                        from: reminder.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger)
            center.add(request)
        }
    }

    func fireTestReminder() {
        let index = Int.random(in: ReminderMessages.all.indices)
        let message = ReminderMessages.all[index]
        let content = UNMutableNotificationContent()
        content.title = "测试 · " + message.title
        content.body = message.body
        content.sound = .default
        content.categoryIdentifier = Self.categoryIdentifier
        content.userInfo = ["messageIndex": index, "test": true]
        let request = UNNotificationRequest(
            identifier: "test-\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let identifier = response.notification.request.identifier
        DispatchQueue.main.async { [weak self] in
            self?.onAction?(response.actionIdentifier, identifier)
        }
        completionHandler()
    }
}
