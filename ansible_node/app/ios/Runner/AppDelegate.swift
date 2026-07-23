import Flutter
import NaturalLanguage
import CryptoKit
import LocalAuthentication
import CoreNFC
import NFCPassportReader
import Security
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  /// Pending Flutter results waiting for an APNS device token (see
  /// registerPushTokenChannel). Completed by the register-success/-failure
  /// callbacks below; APNS wakes are content-free (`{"hint":"sync"}`), so no
  /// notification payload ever crosses this channel.
  private var pendingPushTokenResults: [FlutterResult] = []
  private var pushTokenChannel: FlutterMethodChannel?
  private let zkPassportProver = ZKPassportProver()
  private let zkPassportInputRuntime = ZKPassportInputRuntime()
  private var passportMRZScanner: PassportMRZScanner?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    registerBackupPolicyChannel()
    registerEmbeddingChannel()
    registerPushTokenChannel()
    registerHardwareIdentityKeyChannel()
    registerPassportNfcChannel()
    registerZKPassportProverChannel()
    registerPassportMRZChannel()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func registerPassportMRZChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else { return }
    let scanner = PassportMRZScanner(presenter: controller)
    passportMRZScanner = scanner
    let channel = FlutterMethodChannel(
      name: "elix/passport_mrz",
      binaryMessenger: controller.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "scan" else {
        result(FlutterMethodNotImplemented)
        return
      }
      scanner.scan(result: result)
    }
  }

  private func registerZKPassportProverChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else { return }
    let channel = FlutterMethodChannel(
      name: "elix/zkpassport_prover",
      binaryMessenger: controller.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      guard let args = call.arguments as? [String: Any] else {
        result(FlutterError(code: "invalid_arguments", message: "Missing prover arguments", details: nil))
        return
      }
      let complete: (Result<Any, Error>) -> Void = { outcome in
        DispatchQueue.main.async {
          switch outcome {
          case .success(let value): result(value)
          case .failure(let error):
            result(FlutterError(code: "zkpassport_prover_failed", message: error.localizedDescription, details: nil))
          }
        }
      }
      switch call.method {
      case "plan":
        guard #available(iOS 15.0, *),
              let runtime = args["runtime_javascript"] as? String,
              let request = args["request"] as? [String: Any] else {
          result(FlutterError(code: "invalid_arguments", message: "Missing ZKPassport runtime input", details: nil))
          return
        }
        Task { @MainActor in
          self.zkPassportInputRuntime.createProofPlan(
            runtimeJavaScript: runtime,
            request: request
          ) { outcome in complete(outcome.map { $0 as Any }) }
        }
      case "prepare":
        guard let manifest = args["manifest_json"] as? String,
              let size = args["circuit_size"] as? Int,
              let srsPath = args["srs_path"] as? String,
              !srsPath.isEmpty else {
          result(FlutterError(code: "invalid_arguments", message: "Missing pinned circuit artifacts", details: nil))
          return
        }
        self.zkPassportProver.prepare(
          manifestJSON: manifest,
          circuitSize: UInt32(size),
          srsPath: srsPath
        ) { outcome in complete(outcome.map { $0 as Any }) }
      case "prove":
        guard let circuitID = args["circuit_id"] as? String,
              let inputs = args["inputs"] as? [String: Any],
              let vkey = args["verification_key"] as? FlutterStandardTypedData else {
          result(FlutterError(code: "invalid_arguments", message: "Missing proof input", details: nil))
          return
        }
        self.zkPassportProver.prove(
          circuitID: circuitID,
          inputs: inputs,
          verificationKey: vkey.data
        ) { outcome in complete(outcome.map { FlutterStandardTypedData(bytes: $0) as Any }) }
      case "verify":
        guard let circuitID = args["circuit_id"] as? String,
              let proof = args["proof"] as? FlutterStandardTypedData,
              let vkey = args["verification_key"] as? FlutterStandardTypedData else {
          result(FlutterError(code: "invalid_arguments", message: "Missing verification input", details: nil))
          return
        }
        self.zkPassportProver.verify(
          circuitID: circuitID,
          proof: proof.data,
          verificationKey: vkey.data
        ) { outcome in complete(outcome.map { $0 as Any }) }
      case "clear":
        self.zkPassportProver.clear()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func registerPassportNfcChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else { return }
    let channel = FlutterMethodChannel(
      name: "elix/passport_nfc",
      binaryMessenger: controller.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "isAvailable":
        result(NFCTagReaderSession.readingAvailable)
      case "scan":
        guard #available(iOS 15.0, *),
              let args = call.arguments as? [String: Any],
              let mrzKey = args["mrz_key"] as? String,
              let trustedCscaPem = args["trusted_csca_pem"] as? String,
              !mrzKey.isEmpty,
              !trustedCscaPem.isEmpty else {
          result(FlutterError(
            code: "invalid_arguments",
            message: "Missing MRZ access key or trusted CSCA list.",
            details: nil
          ))
          return
        }
        Task { @MainActor in
          let trustListUrl = FileManager.default.temporaryDirectory
            .appendingPathComponent("elix-csca-\(UUID().uuidString).pem")
          do {
            try Data(trustedCscaPem.utf8).write(
              to: trustListUrl,
              options: [.atomic, .completeFileProtection]
            )
            defer { try? FileManager.default.removeItem(at: trustListUrl) }

            let reader = PassportReader(masterListURL: trustListUrl)
            let passport = try await reader.readPassport(
              mrzKey: mrzKey,
              tags: [.COM, .DG1, .DG14, .DG15, .SOD],
              skipSecureElements: true,
              skipCA: false,
              skipPACE: false
            )
            guard let dg1 = passport.getDataGroup(.DG1),
                  let sod = passport.getDataGroup(.SOD) else {
              throw NSError(
                domain: "ElixPassportNfc",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Passport DG1 or SOD was not returned."]
              )
            }
            result([
              "document_number": passport.documentNumber,
              "date_of_birth": passport.dateOfBirth,
              "date_of_expiry": passport.documentExpiryDate,
              "nationality": passport.nationality,
              "mrz": passport.passportMRZ,
              "dg1": FlutterStandardTypedData(bytes: Data(dg1.data)),
              "sod": FlutterStandardTypedData(bytes: Data(sod.data)),
              "sod_signature_verified": passport.documentSigningCertificateVerified,
              "data_group_hashes_verified": passport.passportDataNotTampered,
              "country_signing_certificate_verified": passport.passportCorrectlySigned,
              "active_authentication_verified": passport.activeAuthenticationPassed,
            ])
          } catch {
            try? FileManager.default.removeItem(at: trustListUrl)
            result(FlutterError(
              code: "passport_scan_failed",
              message: self.passportNfcErrorMessage(error),
              details: nil
            ))
          }
        }
      case "cancel":
        // Core NFC presents its own cancel control. The native reader invalidates
        // the session when the user cancels or the read completes.
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func passportNfcErrorMessage(_ error: Error) -> String {
    let message = error.localizedDescription
    let normalized = message.lowercased()
    if normalized.contains("user canceled") || normalized.contains("invalidated by user") {
      return "Passport scan cancelled."
    }
    if normalized.contains("tag") && normalized.contains("lost") {
      return "The passport moved away from the phone. Hold it still and try again."
    }
    if normalized.contains("security status") || normalized.contains("mutual authenticate") {
      return "The passport details do not match the chip. Check the number and dates."
    }
    return message
  }

  private func registerHardwareIdentityKeyChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else { return }
    let channel = FlutterMethodChannel(
      name: "elix/hardware_identity_key",
      binaryMessenger: controller.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      guard let args = call.arguments as? [String: Any],
            let alias = args["alias"] as? String else {
        result(FlutterError(code: "invalid_arguments", message: "Missing key alias", details: nil))
        return
      }
      do {
        switch call.method {
        case "generate":
          result(try self.generateHardwareIdentityKey(alias: alias))
        case "load":
          result(try self.loadHardwareIdentityKey(alias: alias))
        case "sign":
          guard let message = args["message"] as? FlutterStandardTypedData else {
            result(FlutterError(code: "invalid_arguments", message: "Missing message", details: nil))
            return
          }
          result(try self.signWithHardwareIdentityKey(alias: alias, message: message.data))
        case "generateAgreement":
          result(try self.generateHardwareAgreementKey(alias: alias))
        case "loadAgreement":
          result(try self.loadHardwareAgreementKey(alias: alias))
        case "deriveAgreement":
          guard let peerPublicKeyHex = args["peer_public_key_hex"] as? String else {
            result(FlutterError(code: "invalid_arguments", message: "Missing peer public key", details: nil))
            return
          }
          result(FlutterStandardTypedData(bytes: try self.deriveHardwareAgreement(
            alias: alias,
            peerPublicKeyHex: peerPublicKeyHex
          )))
        case "deleteAgreement":
          try self.deleteHardwareIdentityKey(alias: alias)
          result(nil)
        case "delete":
          try self.deleteHardwareIdentityKey(alias: alias)
          result(nil)
        case "verify":
          guard let message = args["message"] as? FlutterStandardTypedData,
                let publicKeyHex = args["public_key_hex"] as? String,
                let signatureHex = args["signature_hex"] as? String else {
            result(FlutterError(code: "invalid_arguments", message: "Missing verification input", details: nil))
            return
          }
          result(self.verifyP256(publicKeyHex: publicKeyHex, message: message.data, signatureHex: signatureHex))
        default:
          result(FlutterMethodNotImplemented)
        }
      } catch {
        result(FlutterError(code: "hardware_key_failed", message: error.localizedDescription, details: nil))
      }
    }
  }

  private func keychainQuery(alias: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "cool.elix.identity-key",
      kSecAttrAccount as String: alias,
    ]
  }

  private func loadSecureEnclaveKey(alias: String) throws -> SecureEnclave.P256.Signing.PrivateKey? {
    var query = keychainQuery(alias: alias)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = item as? Data else {
      throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
    }
    let context = LAContext()
    context.localizedReason = "Sign with your Elix identity"
    return try SecureEnclave.P256.Signing.PrivateKey(
      dataRepresentation: data,
      authenticationContext: context
    )
  }

  private func keyResult(_ key: SecureEnclave.P256.Signing.PrivateKey) -> [String: Any] {
    [
      "algorithm": "p256-sha256",
      "public_key_hex": key.publicKey.x963Representation.map { String(format: "%02x", $0) }.joined(),
      "custody": "hardware",
      "hardware_security_level": "secure_enclave",
    ]
  }

  private func loadSecureEnclaveAgreementKey(alias: String) throws -> SecureEnclave.P256.KeyAgreement.PrivateKey? {
    var query = keychainQuery(alias: alias)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = item as? Data else {
      throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
    }
    let context = LAContext()
    context.localizedReason = "Unlock your private board key"
    return try SecureEnclave.P256.KeyAgreement.PrivateKey(
      dataRepresentation: data,
      authenticationContext: context
    )
  }

  private func agreementKeyResult(_ key: SecureEnclave.P256.KeyAgreement.PrivateKey) -> [String: Any] {
    [
      "algorithm": "p256-ecdh",
      "public_key_hex": key.publicKey.x963Representation.map { String(format: "%02x", $0) }.joined(),
      "custody": "hardware",
      "hardware_security_level": "secure_enclave",
    ]
  }

  private func generateHardwareAgreementKey(alias: String) throws -> [String: Any] {
    if let existing = try loadSecureEnclaveAgreementKey(alias: alias) {
      return agreementKeyResult(existing)
    }
    var error: Unmanaged<CFError>?
    guard let access = SecAccessControlCreateWithFlags(
      nil,
      kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
      [.privateKeyUsage, .userPresence],
      &error
    ) else { throw error!.takeRetainedValue() as Error }
    let context = LAContext()
    context.localizedReason = "Create your private board key"
    let key = try SecureEnclave.P256.KeyAgreement.PrivateKey(
      accessControl: access,
      authenticationContext: context
    )
    var query = keychainQuery(alias: alias)
    query[kSecValueData as String] = key.dataRepresentation
    query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    let status = SecItemAdd(query as CFDictionary, nil)
    guard status == errSecSuccess else {
      throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
    }
    return agreementKeyResult(key)
  }

  private func loadHardwareAgreementKey(alias: String) throws -> [String: Any]? {
    guard let key = try loadSecureEnclaveAgreementKey(alias: alias) else { return nil }
    return agreementKeyResult(key)
  }

  private func deriveHardwareAgreement(alias: String, peerPublicKeyHex: String) throws -> Data {
    guard let key = try loadSecureEnclaveAgreementKey(alias: alias) else {
      throw NSError(domain: "ElixHardwareKey", code: 2, userInfo: [NSLocalizedDescriptionKey: "Agreement key not found"])
    }
    guard let peerData = Data(hex: peerPublicKeyHex) else {
      throw NSError(domain: "ElixHardwareKey", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid peer public key"])
    }
    let peer = try P256.KeyAgreement.PublicKey(x963Representation: peerData)
    let secret = try key.sharedSecretFromKeyAgreement(with: peer)
    return secret.withUnsafeBytes { Data($0) }
  }

  private func generateHardwareIdentityKey(alias: String) throws -> [String: Any] {
    if let existing = try loadSecureEnclaveKey(alias: alias) { return keyResult(existing) }
    var error: Unmanaged<CFError>?
    guard let access = SecAccessControlCreateWithFlags(
      nil,
      kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
      [.privateKeyUsage, .userPresence],
      &error
    ) else { throw error!.takeRetainedValue() as Error }
    let context = LAContext()
    context.localizedReason = "Create your Elix identity"
    let key = try SecureEnclave.P256.Signing.PrivateKey(
      accessControl: access,
      authenticationContext: context
    )
    var query = keychainQuery(alias: alias)
    query[kSecValueData as String] = key.dataRepresentation
    query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    let status = SecItemAdd(query as CFDictionary, nil)
    guard status == errSecSuccess else {
      throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
    }
    return keyResult(key)
  }

  private func loadHardwareIdentityKey(alias: String) throws -> [String: Any]? {
    guard let key = try loadSecureEnclaveKey(alias: alias) else { return nil }
    return keyResult(key)
  }

  private func signWithHardwareIdentityKey(alias: String, message: Data) throws -> [String: Any] {
    guard let key = try loadSecureEnclaveKey(alias: alias) else {
      throw NSError(domain: "ElixHardwareKey", code: 1, userInfo: [NSLocalizedDescriptionKey: "Identity key not found"])
    }
    let signature = try key.signature(for: message)
    return [
      "algorithm": "p256-sha256",
      "signature_hex": signature.derRepresentation.map { String(format: "%02x", $0) }.joined(),
    ]
  }

  private func deleteHardwareIdentityKey(alias: String) throws {
    let status = SecItemDelete(keychainQuery(alias: alias) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
    }
  }

  private func verifyP256(publicKeyHex: String, message: Data, signatureHex: String) -> Bool {
    guard let publicData = Data(hex: publicKeyHex),
          let signatureData = Data(hex: signatureHex),
          let publicKey = try? P256.Signing.PublicKey(x963Representation: publicData),
          let signature = try? P256.Signing.ECDSASignature(derRepresentation: signatureData) else {
      return false
    }
    return publicKey.isValidSignature(signature, for: message)
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

private extension Data {
  init?(hex: String) {
    guard hex.count.isMultiple(of: 2) else { return nil }
    var data = Data(capacity: hex.count / 2)
    var index = hex.startIndex
    while index < hex.endIndex {
      let next = hex.index(index, offsetBy: 2)
      guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
      data.append(byte)
      index = next
    }
    self = data
  }
}
