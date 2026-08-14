import UIKit
import UserNotifications

/// 回访提醒。
///
/// 回访完成率是这个产品的单点故障：选择不转化成结果，就没有洞察，
/// 也就没有产品。但 PRD 14.3 又要求不催促、不制造焦虑 ——
/// 所以只发一条，文案是「我记得」而不是「你该打分了」，且永远不重复轰炸。
enum FollowUpScheduler {

    /// 用户点了回访通知。RootViewController 收到之后走 resume()。
    static let didTapFollowUp = Notification.Name("FollowUpScheduler.didTapFollowUp")

    /// 拿授权，然后才排提醒。
    ///
    /// 这两件事必须串起来。之前是紧挨着的两行 —— 请求是异步的，
    /// 于是第一条记录 `add` 的时候用户还没点「允许」，系统直接拒掉，
    /// 而且 `add` 的错误没人看：提醒就这么静默地没了。偏偏第一条是最不能丢的那条，
    /// 用户还没体验过一次回访，就已经不会再回来了。
    ///
    /// 已经授权过的情况下 `requestAuthorization` 不会再弹窗，直接回结果，
    /// 所以不需要先 `getNotificationSettings` 探一次。
    static func requestAuthorization(_ completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { granted, _ in
                DispatchQueue.main.async { completion(granted) }
            }
    }

    static func schedule(for episode: DecisionEpisode) {
        let interval = episode.followUpAt.timeIntervalSinceNow
        guard interval > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "上次说的事"
        // 不用感叹号、不催进度。它只是提起，不是提醒你欠了什么。
        content.body = "你选了「\(episode.chosenTitle ?? "")」。现在感觉怎么样？"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: episode.id.uuidString,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }

    static func cancel(_ episode: DecisionEpisode) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [episode.id.uuidString])
    }
}


/// 点通知直接回到那件事上。
final class FollowUpNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {

    static let shared = FollowUpNotificationDelegate()

    func install() {
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        NotificationCenter.default.post(name: FollowUpScheduler.didTapFollowUp, object: nil)
    }

    /// App 正在前台用着的时候不弹横幅 —— 界面上已经是那件事了，再弹一次是打扰。
    ///
    /// **只在前台。** 这里原本无条件返回 `[]`，看起来等价，实际不是：
    /// 退到后台之后进程还活着，系统照样来问这一句，于是横幅被自己吞掉了 ——
    /// 而「按 home 键出去、过一会儿收到提醒」正是最常见的那条路径。
    /// 日志里这个 bug 只留下一行 `Send willPresentNotification`，界面上什么都不发生。
    @MainActor
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        UIApplication.shared.applicationState == .active ? [] : [.banner, .sound, .list]
    }
}
