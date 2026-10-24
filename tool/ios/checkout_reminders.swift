// Appended to the generated AppDelegate.swift by prepare_ios.sh.
// Local notifications are reminders only; a payload never authorizes checkout.
final class SkoCheckoutReminders: NSObject, UNUserNotificationCenterDelegate {
  private static let prefix = "sko.checkout.reminder."
  private static let registryKey = "sko.checkout.reminder.identifiers.v1"
  private static let tapKey = "sko.checkout.reminder.pendingTap.v1"
  private let center = UNUserNotificationCenter.current()
  private let channel: FlutterMethodChannel
  private weak var previousDelegate: UNUserNotificationCenterDelegate?
  // All mutations and command callbacks run on the main queue. Invalidate an
  // authorization request when logout/cancellation arrives before its callback.
  private var epoch = 0
  private var revisions: [String: Int] = [:]
  private var identifiers: Set<String>

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "com.skworks.skWorks/checkout-reminders", binaryMessenger: messenger)
    identifiers = Set(UserDefaults.standard.stringArray(forKey: Self.registryKey) ?? [])
    super.init()
    previousDelegate = center.delegate
    center.delegate = self
    channel.setMethodCallHandler { [weak self] call, result in
      DispatchQueue.main.async {
        guard let self = self else { result(FlutterError(code: "unavailable", message: "Reminder unavailable", details: nil)); return }
        self.handle(call, result: result)
      }
    }
  }

  private func saveIdentifiers() {
    UserDefaults.standard.set(Array(identifiers).sorted(), forKey: Self.registryKey)
  }

  private static func validSource(_ value: String) -> Bool {
    !value.isEmpty && value.utf8.count <= 160 &&
      value.range(of: "^[A-Za-z0-9:_-]+$", options: .regularExpression) != nil
  }

  private static func status(_ settings: UNNotificationSettings) -> String {
    switch settings.authorizationStatus {
    case .authorized: return "authorized"
    case .provisional: return "provisional"
    case .ephemeral: return "ephemeral"
    case .denied: return "denied"
    case .notDetermined: return "notDetermined"
    @unknown default: return "unknown"
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "status":
      center.getNotificationSettings { settings in
        DispatchQueue.main.async { result(Self.status(settings)) }
      }
    case "requestPermission":
      center.requestAuthorization(options: [.alert, .sound, .badge]) { _, error in
        if let error = error {
          DispatchQueue.main.async { result(FlutterError(code: "permission_request_failed", message: error.localizedDescription, details: nil)) }
          return
        }
        self.center.getNotificationSettings { settings in
          DispatchQueue.main.async { result(Self.status(settings)) }
        }
      }
    case "schedule": schedule(call.arguments, result: result)
    case "cancel":
      guard let args = call.arguments as? [String: Any], let source = args["sourceId"] as? String,
            Self.validSource(source) else {
        result(FlutterError(code: "bad_args", message: "Invalid reminder source", details: nil)); return
      }
      revisions[source, default: 0] += 1
      let matching = identifiers.filter { $0.hasPrefix(Self.prefix + source + ".") }
      identifiers.subtract(matching)
      saveIdentifiers()
      center.removePendingNotificationRequests(withIdentifiers: Array(matching))
      center.removeDeliveredNotifications(withIdentifiers: Array(matching))
      if UserDefaults.standard.string(forKey: Self.tapKey) == source { UserDefaults.standard.removeObject(forKey: Self.tapKey) }
      removeUntrackedRequests(prefix: Self.prefix + source + ".", result: result)
    case "cancelAll":
      epoch += 1
      revisions.removeAll()
      // Cancel only this feature, preserving every other app notification.
      let previous = Array(identifiers)
      identifiers.removeAll()
      saveIdentifiers()
      UserDefaults.standard.removeObject(forKey: Self.tapKey)
      center.removePendingNotificationRequests(withIdentifiers: previous)
      center.removeDeliveredNotifications(withIdentifiers: previous)
      removeUntrackedRequests(prefix: Self.prefix, result: result)
    case "consumePendingTap":
      let source = UserDefaults.standard.string(forKey: Self.tapKey)
      UserDefaults.standard.removeObject(forKey: Self.tapKey)
      result(source.flatMap { Self.validSource($0) ? $0 : nil })
    default: result(FlutterMethodNotImplemented)
    }
  }

  // Reconcile OS-owned requests too, e.g. if process termination interrupted
  // registry persistence. Unique current-attempt IDs protect newer schedules
  // started while these asynchronous enumeration callbacks are pending.
  private func removeUntrackedRequests(prefix: String, result: @escaping FlutterResult) {
    let group = DispatchGroup()
    group.enter()
    center.getPendingNotificationRequests { requests in
      DispatchQueue.main.async {
        let stale = requests.map { $0.identifier }.filter { $0.hasPrefix(prefix) && !self.identifiers.contains($0) }
        self.center.removePendingNotificationRequests(withIdentifiers: stale)
        group.leave()
      }
    }
    group.enter()
    center.getDeliveredNotifications { notifications in
      DispatchQueue.main.async {
        let stale = notifications.map { $0.request.identifier }.filter { $0.hasPrefix(prefix) && !self.identifiers.contains($0) }
        self.center.removeDeliveredNotifications(withIdentifiers: stale)
        group.leave()
      }
    }
    group.notify(queue: .main) { result(true) }
  }

  private func schedule(_ value: Any?, result: @escaping FlutterResult) {
    guard let args = value as? [String: Any], let source = args["sourceId"] as? String,
          Self.validSource(source), let number = args["fireAtEpochMs"] as? NSNumber else {
      result(FlutterError(code: "bad_args", message: "Invalid reminder", details: nil)); return
    }
    let millis = number.doubleValue
    guard millis.isFinite else {
      result(FlutterError(code: "bad_time", message: "Invalid reminder time", details: nil)); return
    }
    let fireAt = Date(timeIntervalSince1970: millis / 1000)
    let delay = fireAt.timeIntervalSinceNow
    guard millis.isFinite, delay > 0, delay <= 8 * 24 * 60 * 60 else {
      result(FlutterError(code: "bad_time", message: "Reminder must be within the next eight days", details: nil)); return
    }
    let capturedEpoch = epoch
    revisions[source, default: 0] += 1
    let revision = revisions[source]!
    center.getNotificationSettings { settings in
      DispatchQueue.main.async {
        guard self.epoch == capturedEpoch, self.revisions[source] == revision else {
          result(FlutterError(code: "cancelled", message: "Reminder cancelled", details: nil)); return
        }
        guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else {
          result(FlutterError(code: "permission_denied", message: "Notification permission unavailable", details: nil)); return
        }
        let remaining = fireAt.timeIntervalSinceNow
        guard remaining > 0 else {
          result(FlutterError(code: "bad_time", message: "Reminder time passed", details: nil)); return
        }
        let replaced = self.identifiers.filter { $0.hasPrefix(Self.prefix + source + ".") }
        self.identifiers.subtract(replaced)
        self.center.removePendingNotificationRequests(withIdentifiers: Array(replaced))
        self.center.removeDeliveredNotifications(withIdentifiers: Array(replaced))
        // Unique attempt identifier prevents a late cancelled callback from
        // removing a newer schedule for this same source.
        let identifier = Self.prefix + source + "." + UUID().uuidString
        let content = UNMutableNotificationContent()
        // Generic lock-screen text only. No names, company, wage or credentials.
        content.title = "SKO｜退勤の確認"
        content.body = "退勤予定時刻です。勤務状況を確認してください。"
        content.sound = .default
        content.userInfo = ["skoCheckoutSourceId": source]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, remaining), repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        self.identifiers.insert(identifier)
        self.saveIdentifiers()
        self.center.removePendingNotificationRequests(withIdentifiers: [identifier])
        self.center.add(request) { error in
          DispatchQueue.main.async {
            guard self.epoch == capturedEpoch, self.revisions[source] == revision else {
              self.center.removePendingNotificationRequests(withIdentifiers: [identifier])
              self.center.removeDeliveredNotifications(withIdentifiers: [identifier])
              self.identifiers.remove(identifier)
              self.saveIdentifiers()
              result(FlutterError(code: "cancelled", message: "Reminder cancelled", details: nil)); return
            }
            if let error = error {
              self.identifiers.remove(identifier)
              self.saveIdentifiers()
              result(FlutterError(code: "schedule_failed", message: error.localizedDescription, details: nil))
            } else { result("scheduled") }
          }
        }
      }
    }
  }

  private func ownSource(_ notification: UNNotification) -> String? {
    guard let source = notification.request.content.userInfo["skoCheckoutSourceId"] as? String,
          Self.validSource(source), notification.request.identifier.hasPrefix(Self.prefix + source + "."),
          identifiers.contains(notification.request.identifier) else { return nil }
    return source
  }

  func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                              withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    if notification.request.identifier.hasPrefix(Self.prefix) {
      DispatchQueue.main.async {
        guard let source = self.ownSource(notification) else { completionHandler([]); return }
        self.channel.invokeMethod("notificationDue", arguments: source)
        completionHandler([.banner, .list, .sound])
      }
    } else if let previous = previousDelegate, previous.responds(to: #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:willPresent:withCompletionHandler:))) {
      previous.userNotificationCenter?(center, willPresent: notification, withCompletionHandler: completionHandler)
    } else { completionHandler([]) }
  }

  func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                              withCompletionHandler completionHandler: @escaping () -> Void) {
    if response.notification.request.identifier.hasPrefix(Self.prefix) {
      DispatchQueue.main.async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let source = self.ownSource(response.notification) else { completionHandler(); return }
        UserDefaults.standard.set(source, forKey: Self.tapKey)
        self.channel.invokeMethod("notificationTapped", arguments: source) { ack in
          if ack as? Bool == true, UserDefaults.standard.string(forKey: Self.tapKey) == source {
            UserDefaults.standard.removeObject(forKey: Self.tapKey)
          }
        }
        completionHandler()
      }
    } else if let previous = previousDelegate, previous.responds(to: #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:))) {
      previous.userNotificationCenter?(center, didReceive: response, withCompletionHandler: completionHandler)
    } else { completionHandler() }
  }
}
