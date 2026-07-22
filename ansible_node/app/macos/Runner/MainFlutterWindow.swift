import Cocoa
import CryptoKit
import FlutterMacOS
import LocalAuthentication
import Security

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController.init()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    HardwareIdentityKeyChannel.register(with: flutterViewController)

    super.awakeFromNib()
  }
}

private enum HardwareIdentityKeyChannel {
  static func register(with controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "elix/hardware_identity_key",
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      guard let args = call.arguments as? [String: Any],
            let alias = args["alias"] as? String,
            !alias.isEmpty else {
        result(FlutterError(code: "invalid_arguments", message: "Missing key alias", details: nil))
        return
      }
      do {
        switch call.method {
        case "generate": result(try generate(alias: alias))
        case "load": result(try load(alias: alias))
        case "sign":
          guard let message = args["message"] as? FlutterStandardTypedData else {
            result(FlutterError(code: "invalid_arguments", message: "Missing message", details: nil))
            return
          }
          result(try sign(alias: alias, message: message.data))
        case "generateAgreement": result(try generateAgreement(alias: alias))
        case "loadAgreement": result(try loadAgreement(alias: alias))
        case "deriveAgreement":
          guard let peerPublicKeyHex = args["peer_public_key_hex"] as? String else {
            result(FlutterError(code: "invalid_arguments", message: "Missing peer public key", details: nil))
            return
          }
          result(FlutterStandardTypedData(bytes: try deriveAgreement(
            alias: alias,
            peerPublicKeyHex: peerPublicKeyHex
          )))
        case "deleteAgreement":
          try delete(alias: alias)
          result(nil)
        case "delete":
          try delete(alias: alias)
          result(nil)
        case "verify":
          guard let message = args["message"] as? FlutterStandardTypedData,
                let publicKeyHex = args["public_key_hex"] as? String,
                let signatureHex = args["signature_hex"] as? String else {
            result(FlutterError(code: "invalid_arguments", message: "Missing verification input", details: nil))
            return
          }
          result(verify(publicKeyHex: publicKeyHex, message: message.data, signatureHex: signatureHex))
        default: result(FlutterMethodNotImplemented)
        }
      } catch {
        result(FlutterError(code: "hardware_key_failed", message: error.localizedDescription, details: nil))
      }
    }
  }

  private static func query(alias: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "cool.elix.hardware-key",
      kSecAttrAccount as String: alias,
    ]
  }

  private static func privateKey(alias: String) throws -> SecureEnclave.P256.Signing.PrivateKey? {
    var request = query(alias: alias)
    request[kSecReturnData as String] = true
    request[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    let status = SecItemCopyMatching(request as CFDictionary, &item)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = item as? Data else {
      throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
    }
    let context = LAContext()
    context.localizedReason = "Sign with your Elix hardware key"
    return try SecureEnclave.P256.Signing.PrivateKey(
      dataRepresentation: data,
      authenticationContext: context
    )
  }

  private static func response(_ key: SecureEnclave.P256.Signing.PrivateKey) -> [String: Any] {
    [
      "algorithm": "p256-sha256",
      "public_key_hex": key.publicKey.x963Representation.hex,
      "custody": "hardware",
      "hardware_security_level": "secure_enclave",
    ]
  }

  private static func agreementPrivateKey(alias: String) throws -> SecureEnclave.P256.KeyAgreement.PrivateKey? {
    var request = query(alias: alias)
    request[kSecReturnData as String] = true
    request[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    let status = SecItemCopyMatching(request as CFDictionary, &item)
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

  private static func agreementResponse(_ key: SecureEnclave.P256.KeyAgreement.PrivateKey) -> [String: Any] {
    [
      "algorithm": "p256-ecdh",
      "public_key_hex": key.publicKey.x963Representation.hex,
      "custody": "hardware",
      "hardware_security_level": "secure_enclave",
    ]
  }

  private static func generateAgreement(alias: String) throws -> [String: Any] {
    if let existing = try agreementPrivateKey(alias: alias) { return agreementResponse(existing) }
    var accessError: Unmanaged<CFError>?
    guard let access = SecAccessControlCreateWithFlags(
      nil,
      kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
      [.privateKeyUsage, .userPresence],
      &accessError
    ) else { throw accessError!.takeRetainedValue() as Error }
    let context = LAContext()
    context.localizedReason = "Create your private board key"
    let key = try SecureEnclave.P256.KeyAgreement.PrivateKey(
      accessControl: access,
      authenticationContext: context
    )
    var request = query(alias: alias)
    request[kSecValueData as String] = key.dataRepresentation
    request[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    let status = SecItemAdd(request as CFDictionary, nil)
    guard status == errSecSuccess else {
      throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
    }
    return agreementResponse(key)
  }

  private static func loadAgreement(alias: String) throws -> [String: Any]? {
    guard let key = try agreementPrivateKey(alias: alias) else { return nil }
    return agreementResponse(key)
  }

  private static func deriveAgreement(alias: String, peerPublicKeyHex: String) throws -> Data {
    guard let key = try agreementPrivateKey(alias: alias) else {
      throw NSError(domain: "ElixHardwareKey", code: 2, userInfo: [NSLocalizedDescriptionKey: "Agreement key not found"])
    }
    guard let peerData = Data(hex: peerPublicKeyHex) else {
      throw NSError(domain: "ElixHardwareKey", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid peer public key"])
    }
    let peer = try P256.KeyAgreement.PublicKey(x963Representation: peerData)
    return try key.sharedSecretFromKeyAgreement(with: peer).withUnsafeBytes { Data($0) }
  }

  private static func generate(alias: String) throws -> [String: Any] {
    if let existing = try privateKey(alias: alias) { return response(existing) }
    var accessError: Unmanaged<CFError>?
    guard let access = SecAccessControlCreateWithFlags(
      nil,
      kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
      [.privateKeyUsage, .userPresence],
      &accessError
    ) else { throw accessError!.takeRetainedValue() as Error }
    let context = LAContext()
    context.localizedReason = "Create your Elix hardware key"
    let key = try SecureEnclave.P256.Signing.PrivateKey(
      accessControl: access,
      authenticationContext: context
    )
    var request = query(alias: alias)
    request[kSecValueData as String] = key.dataRepresentation
    request[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    let status = SecItemAdd(request as CFDictionary, nil)
    guard status == errSecSuccess else {
      throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
    }
    return response(key)
  }

  private static func load(alias: String) throws -> [String: Any]? {
    guard let key = try privateKey(alias: alias) else { return nil }
    return response(key)
  }

  private static func sign(alias: String, message: Data) throws -> [String: Any] {
    guard let key = try privateKey(alias: alias) else {
      throw NSError(domain: "ElixHardwareKey", code: 1, userInfo: [NSLocalizedDescriptionKey: "Hardware key not found"])
    }
    return [
      "algorithm": "p256-sha256",
      "signature_hex": try key.signature(for: message).derRepresentation.hex,
    ]
  }

  private static func delete(alias: String) throws {
    let status = SecItemDelete(query(alias: alias) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
    }
  }

  private static func verify(publicKeyHex: String, message: Data, signatureHex: String) -> Bool {
    guard let publicData = Data(hex: publicKeyHex),
          let signatureData = Data(hex: signatureHex),
          let key = try? P256.Signing.PublicKey(x963Representation: publicData),
          let signature = try? P256.Signing.ECDSASignature(derRepresentation: signatureData) else {
      return false
    }
    return key.isValidSignature(signature, for: message)
  }
}

private extension Data {
  var hex: String { map { String(format: "%02x", $0) }.joined() }

  init?(hex: String) {
    guard hex.count.isMultiple(of: 2) else { return nil }
    var bytes = [UInt8]()
    bytes.reserveCapacity(hex.count / 2)
    var index = hex.startIndex
    while index < hex.endIndex {
      let next = hex.index(index, offsetBy: 2)
      guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
      bytes.append(byte)
      index = next
    }
    self.init(bytes)
  }
}
