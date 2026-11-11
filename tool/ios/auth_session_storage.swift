import Foundation
import Security
import Flutter

// Unregistered preparation source. No generated AppDelegate registration yet.
protocol SKOAuthEnvelopeStore {
  func read(account: String) throws -> Data?
  func write(account: String, data: Data) throws
}

enum SKOAuthStorageError: Error { case unavailable }

final class SKOAuthKeychainEnvelopeStore: SKOAuthEnvelopeStore {
  private static let service = "com.skworks.skWorks.auth-session.v1"
  private func query(_ account: String) -> [String: Any] {
    [kSecClass as String: kSecClassGenericPassword,
     kSecAttrService as String: Self.service,
     kSecAttrAccount as String: account,
     kSecAttrSynchronizable as String: false,
     kSecUseDataProtectionKeychain as String: true]
  }
  func read(account: String) throws -> Data? {
    var q = query(account)
    q[kSecReturnData as String] = true
    q[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(q as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = result as? Data else {
      throw SKOAuthStorageError.unavailable
    }
    return data
  }
  func write(account: String, data: Data) throws {
    let q = query(account)
    // Atomic replacement of the complete envelope, never separate token slots.
    let status = SecItemUpdate(q as CFDictionary,
      [kSecValueData as String: data] as CFDictionary)
    if status == errSecSuccess { return }
    guard status == errSecItemNotFound else { throw SKOAuthStorageError.unavailable }
    var add = q
    add[kSecValueData as String] = data
    add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else {
      // Duplicate or unknown: do not delete/overwrite/retry automatically.
      throw SKOAuthStorageError.unavailable
    }
  }
}

final class SKOAuthSessionStoragePreparationChannel {
  private let channel: FlutterMethodChannel
  private let store: SKOAuthEnvelopeStore
  private let enabled: () -> Bool
  init(messenger: FlutterBinaryMessenger, store: SKOAuthEnvelopeStore,
       enabled: @escaping () -> Bool = { false }) {
    self.store = store
    self.enabled = enabled
    channel = FlutterMethodChannel(name: "com.skworks.sko/auth_session_storage_preparation",
                                   binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self, self.enabled(),
        let arguments = call.arguments as? [String: Any],
        let project = arguments["project"] as? String,
        project.range(of: "^[a-z0-9][a-z0-9.-]{0,127}$", options: .regularExpression) != nil
      else { result(FlutterError(code: "unavailable", message: "Secure storage preparation unavailable.", details: nil)); return }
      do {
        let account = "project." + project + ".envelope.v1"
        if call.method == "read", arguments.count == 1 {
          if let data = try self.store.read(account: account) {
            guard let envelope = String(data: data, encoding: .utf8) else { throw SKOAuthStorageError.unavailable }
            result(["status": "present", "envelope": envelope])
          } else { result(["status": "absent"]) }
        } else if call.method == "write", arguments.count == 2,
          let envelope = arguments["envelope"] as? String, !envelope.isEmpty,
          let data = envelope.data(using: .utf8) {
          try self.store.write(account: account, data: data)
          result(["status": "acknowledged"])
        } else { result(FlutterMethodNotImplemented) }
      } catch {
        result(FlutterError(code: "unavailable", message: "Secure storage result requires reconciliation.", details: nil))
      }
    }
  }
  deinit { channel.setMethodCallHandler(nil) }
}
