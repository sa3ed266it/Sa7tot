import Foundation
import UserNotifications

func newNotification() {
    UNUserNotificationCenter.current().removeAllPendingNotificationRequests()

    let content = UNMutableNotificationContent()
    content.title = String(localized: "Keep the streak going!")
    content.subtitle = String(localized: "Remember to input your expenses today.")
    content.sound = UNNotificationSound.default

    var components = DateComponents()
    let defaults = UserDefaults(suiteName: "group.com.saied.sa7tot") ?? .standard
    let option = defaults.object(forKey: "notificationOption") == nil
        ? 1
        : defaults.integer(forKey: "notificationOption")

    if option == 1 {
        components.hour = 8
        components.minute = 0
    } else if option == 2 {
        components.hour = 20
        components.minute = 0
    } else {
        components.hour = defaults.object(forKey: "customHour") == nil ? 8 : defaults.integer(forKey: "customHour")
        components.minute = defaults.object(forKey: "customMinute") == nil ? 0 : defaults.integer(forKey: "customMinute")
    }

    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
    let request = UNNotificationRequest(
        identifier: UUID().uuidString,
        content: content,
        trigger: trigger
    )
    UNUserNotificationCenter.current().add(request)
}
