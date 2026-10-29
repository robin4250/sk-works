import Foundation
import CryptoKit
import Security
import LocalAuthentication

// Native-only Ed25519 custody; never Secure Enclave/non-exportability attestation.
// Raw key bytes exist only inside this native implementation and Keychain.
enum SKOQRKeyError: Error { case unavailable }
struct SKOQRKeyScope {
  let actor: String, company: String, device: String
  static func validUUID(_ value: String) -> Bool {
    value.range(of: "^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$", options: .regularExpression) != nil
  }
  init(actor: String, company: String, device: String) throws {
    guard [actor, company, device].allSatisfy(Self.validUUID) else { throw SKOQRKeyError.unavailable }
    self.actor = actor; self.company = company; self.device = device
  }
  var handle: String {
    SHA256.hash(data: Data("sko.qr.scanner.custody.v1\n\(actor)\n\(company)\n\(device)".utf8)).map { String(format: "%02x", $0) }.joined()
  }
}

final class SKOQRScannerKeyCustody {
  static let service = "com.skworks.sko.qr-scanner.ed25519.v1"
  static func accessControl() throws -> SecAccessControl {
    var error: Unmanaged<CFError>?
    guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .userPresence, &error) else {
      throw SKOQRKeyError.unavailable
    }
    return access
  }
  static func query(_ scope: SKOQRKeyScope) -> [String: Any] {
    [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
     kSecAttrAccount as String: scope.handle, kSecAttrSynchronizable as String: false,
     kSecUseDataProtectionKeychain as String: true]
  }
  // The channel requires a fresh deviceOwnerAuthentication before invoking this.
  // Keychain independently enforces userPresence on every retrieval.
  static func prepare(_ scope: SKOQRKeyScope, context: LAContext) throws -> [String: String] {
    var q = query(scope); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
    q[kSecUseAuthenticationContext as String] = context
    var value: CFTypeRef?
    let status = SecItemCopyMatching(q as CFDictionary, &value)
    let key: Curve25519.Signing.PrivateKey
    if status == errSecSuccess, let data = value as? Data {
      key = try Curve25519.Signing.PrivateKey(rawRepresentation: data)
    } else if status == errSecItemNotFound {
      key = Curve25519.Signing.PrivateKey()
      var add = query(scope); add[kSecAttrAccessControl as String] = try accessControl()
      add[kSecValueData as String] = key.rawRepresentation
      // Do not update/delete/replace on duplicate or an unknown outcome.
      guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw SKOQRKeyError.unavailable }
    } else { throw SKOQRKeyError.unavailable }
    return ["handle": scope.handle, "publicKeyHex": spki(key.publicKey)]
  }
  static func spki(_ key: Curve25519.Signing.PublicKey) -> String {
    "302a300506032b6570032100" + key.rawRepresentation.map { String(format: "%02x", $0) }.joined()
  }
  static func signingBytes(_ c: [String: Any], scope: SKOQRKeyScope, session: String, publicKey: String) throws -> Data {
    let names = ["id", "company", "actor", "session", "device", "nonce"]
    guard c.count == 10, names.allSatisfy({ (c[$0] as? String).map(SKOQRKeyScope.validUUID) == true }),
      c["actor"] as? String == scope.actor, c["company"] as? String == scope.company,
      c["device"] as? String == scope.device, c["session"] as? String == session,
      c["keyHex"] as? String == publicKey,
      let created = c["createdMs"] as? NSNumber, let expires = c["expiresMs"] as? NSNumber,
      let now = c["databaseNowMs"] as? NSNumber,
      [created, expires, now].allSatisfy({ CFGetTypeID($0) != CFBooleanGetTypeID() && $0.doubleValue.isFinite && $0.doubleValue.rounded() == $0.doubleValue && abs($0.doubleValue) <= 9007199254740991 }),
      expires.int64Value > created.int64Value, expires.int64Value - created.int64Value <= 90000,
      now.int64Value >= created.int64Value, now.int64Value < expires.int64Value else { throw SKOQRKeyError.unavailable }
    return try JSONSerialization.data(withJSONObject: ["sko.qr.scanner.register.key-possession.v1", c["id"]!, scope.company, scope.actor,
      session, scope.device, publicKey, c["nonce"]!, created, expires], options: [.withoutEscapingSlashes])
  }
  static func sign(_ scope: SKOQRKeyScope, session: String, handle: String, challenge: [String: Any], context: LAContext) throws -> [String: String] {
    guard handle == scope.handle, SKOQRKeyScope.validUUID(session) else { throw SKOQRKeyError.unavailable }
    var q = query(scope); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
    q[kSecUseAuthenticationContext as String] = context
    var value: CFTypeRef?
    guard SecItemCopyMatching(q as CFDictionary, &value) == errSecSuccess, let data = value as? Data else { throw SKOQRKeyError.unavailable }
    let key = try Curve25519.Signing.PrivateKey(rawRepresentation: data)
    let bytes = try signingBytes(challenge, scope: scope, session: session, publicKey: spki(key.publicKey))
    let signature = try key.signature(for: bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    return ["handle": handle, "signature": signature]
  }
}

#if canImport(Flutter) && canImport(UIKit)
import Flutter
import UIKit

final class SKOQRScannerKeyChannel {
  private let channel: FlutterMethodChannel
  private var context: LAContext?
  private var pendingID: String?
  private var pendingResult: FlutterResult?
  private var observer: NSObjectProtocol?
  private var expiry: DispatchWorkItem?
  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "com.skworks.sko/qr_scanner_key", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      DispatchQueue.main.async {
        guard let self else { result(FlutterError(code: "unavailable", message: "スキャナー鍵を利用できません。", details: nil)); return }
        self.handle(call, result: result)
      }
    }
    observer = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in self?.cancel() }
  }
  private func cancel() {
    context?.invalidate(); context = nil; expiry?.cancel(); expiry = nil; pendingID = nil
    let result = pendingResult; pendingResult = nil
    result?(FlutterError(code: "unavailable", message: "スキャナー鍵の確認を完了できません。", details: nil))
  }
  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any], let id = args["requestId"] as? String, SKOQRKeyScope.validUUID(id) else {
      result(FlutterError(code: "invalid_request", message: "スキャナー鍵を利用できません。", details: nil)); return
    }
    if call.method == "cancel" { if pendingID == id { cancel(); result(true) } else { result(false) }; return }
    guard ["prepare", "sign"].contains(call.method), pendingID == nil,
      Bundle.main.object(forInfoDictionaryKey: "SKOQRScannerKeyPreparationEnabled") as? Bool == true,
      UIApplication.shared.applicationState == .active,
      args.count == (call.method == "prepare" ? 4 : 7),
      let actor = args["actor"] as? String, let company = args["company"] as? String, let device = args["device"] as? String,
      let scope = try? SKOQRKeyScope(actor: actor, company: company, device: device) else {
      result(FlutterError(code: "unavailable", message: "スキャナー登録は準備中です。", details: nil)); return
    }
    let captured = args, operation = call.method, auth = LAContext(), started = ProcessInfo.processInfo.systemUptime
    auth.touchIDAuthenticationAllowableReuseDuration = 0
    context = auth; pendingID = id; pendingResult = result
    let timeout = DispatchWorkItem { [weak self] in if self?.pendingID == id { self?.cancel() } }
    expiry = timeout; DispatchQueue.main.asyncAfter(deadline: .now() + 90, execute: timeout)
    auth.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "この端末のスキャナー鍵を確認します。") { [weak self] ok, _ in
      DispatchQueue.main.async {
        guard let self, self.pendingID == id else { return }
        guard ok, UIApplication.shared.applicationState == .active, ProcessInfo.processInfo.systemUptime - started < 90 else { self.cancel(); return }
        do {
          let output: [String: String]
          if operation == "prepare" { output = try SKOQRScannerKeyCustody.prepare(scope, context: auth) }
          else {
            guard let session = captured["session"] as? String, let handle = captured["handle"] as? String,
              let challenge = captured["challenge"] as? [String: Any],
              let serverNow = challenge["databaseNowMs"] as? NSNumber, let serverExpiry = challenge["expiresMs"] as? NSNumber,
              (ProcessInfo.processInfo.systemUptime - started) * 1000 < serverExpiry.doubleValue - serverNow.doubleValue else { throw SKOQRKeyError.unavailable }
            output = try SKOQRScannerKeyCustody.sign(scope, session: session, handle: handle, challenge: challenge, context: auth)
          }
          guard self.pendingID == id, UIApplication.shared.applicationState == .active,
            ProcessInfo.processInfo.systemUptime - started < 90 else { self.cancel(); return }
          if operation == "sign" {
            guard let challenge = captured["challenge"] as? [String: Any],
              let now = challenge["databaseNowMs"] as? NSNumber, let end = challenge["expiresMs"] as? NSNumber,
              (ProcessInfo.processInfo.systemUptime - started) * 1000 < end.doubleValue - now.doubleValue else { self.cancel(); return }
          }
          self.expiry?.cancel(); self.expiry = nil; self.context?.invalidate(); self.context = nil
          self.pendingID = nil; let callback = self.pendingResult; self.pendingResult = nil; callback?(output)
        } catch { self.cancel() }
      }
    }
  }
  deinit { context?.invalidate(); expiry?.cancel(); if let observer { NotificationCenter.default.removeObserver(observer) } }
}
#endif
