import Flutter
import NaturalLanguage
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  /// Pending Flutter results waiting for an APNS device token (see
  /// registerPushTokenChannel). Completed by the register-success/-failure
  /// callbacks below; APNS wakes are content-free (`{"hint":"sync"}`), so no
  /// notification payload ever crosses this channel.
  private var pendingPushTokenResults: [FlutterResult] = []
  private var pushTokenChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    registerBackupPolicyChannel()
    registerEmbeddingChannel()
    registerPushTokenChannel()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // ── Push wake token (notification system, Phase B) ─────────────────────────
  // Background wakes need only registerForRemoteNotifications() — no user
  // alert permission — because the relay pushes `apns-push-type: background`
  // with no visible content; the app composes local notifications itself.

  private func registerPushTokenChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "elix/push_token",
      binaryMessenger: controller.binaryMessenger
    )
    pushTokenChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "requestToken" else {
        result(FlutterMethodNotImplemented)
        return
      }
      #if targetEnvironment(simulator)
        // The simulator has no APNS; report "unavailable" instead of hanging.
        result(nil)
      #else
        self?.pendingPushTokenResults.append(result)
        UIApplication.shared.registerForRemoteNotifications()
      #endif
    }
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    super.application(
      application,
      didRegisterForRemoteNotificationsWithDeviceToken: deviceToken
    )
    let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
    for result in pendingPushTokenResults { result(hex) }
    pendingPushTokenResults.removeAll()
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    super.application(
      application,
      didFailToRegisterForRemoteNotificationsWithError: error
    )
    for result in pendingPushTokenResults { result(nil) }
    pendingPushTokenResults.removeAll()
  }

  override func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    // Content-free wake: nudge the Dart side to run a bounded sync pass when
    // the engine is alive (foreground/backgrounded). Cold-start background
    // execution is deliberately out of scope here — opening the app syncs.
    pushTokenChannel?.invokeMethod("wakeReceived", arguments: nil)
    completionHandler(.newData)
  }

  private func registerEmbeddingChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "ansible_node/embedding",
      binaryMessenger: controller.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "embed" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let args = call.arguments as? [String: Any],
        let text = args["text"] as? String
      else {
        result(FlutterError(
          code: "invalid_arguments",
          message: "Missing or invalid 'text' argument",
          details: nil
        ))
        return
      }
      if #available(iOS 14.0, *) {
        if let embedding = NLEmbedding.sentenceEmbedding(for: .traditionalChinese) {
          let vector = embedding.vector(for: text) ?? []
          result(vector)
        } else {
          result(FlutterError(
            code: "model_unavailable",
            message: "NLEmbedding for traditionalChinese not available",
            details: nil
          ))
        }
      } else {
        result(FlutterError(
          code: "unsupported_os",
          message: "Sentence embedding requires iOS 14.0+",
          details: nil
        ))
      }
    }
  }

  private func registerBackupPolicyChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return
    }
    let channel = FlutterMethodChannel(name: "ansible_node/backup_policy", binaryMessenger: controller.binaryMessenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "prepareRemoteMirrorDirectory" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let args = call.arguments as? [String: Any],
        let name = args["name"] as? String,
        !name.isEmpty
      else {
        result(FlutterError(code: "invalid_arguments", message: "Missing no-backup directory name", details: nil))
        return
      }

      do {
        let support = try FileManager.default.url(
          for: .applicationSupportDirectory,
          in: .userDomainMask,
          appropriateFor: nil,
          create: true
        )
        var directory = support.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try directory.setResourceValues(resourceValues)
        result(directory.path)
      } catch {
        result(FlutterError(code: "backup_policy_failed", message: error.localizedDescription, details: nil))
      }
    }
  }
}
