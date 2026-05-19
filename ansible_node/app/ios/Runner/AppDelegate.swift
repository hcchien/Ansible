import Flutter
import NaturalLanguage
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    registerBackupPolicyChannel()
    registerEmbeddingChannel()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
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
