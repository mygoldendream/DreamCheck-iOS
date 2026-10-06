import Foundation

enum MessageSelector {
    static func select(lastMessageIndex: Int?) -> Int {
        let count = ReminderMessages.all.count
        guard let prior = lastMessageIndex, ReminderMessages.all.indices.contains(prior) else {
            return Int.random(in: ReminderMessages.all.indices)
        }
        let selection = Int.random(in: 0..<(count - 1))
        return selection >= prior ? selection + 1 : selection
    }
}
