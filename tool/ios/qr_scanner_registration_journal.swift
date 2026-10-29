import Foundation
import CryptoKit
import Security
import LocalAuthentication

// Non-secret write-ahead state only. No password, bearer, raw proof, signature,
// private key or caller-selected storage account is accepted by this boundary.
final class SKOQRRegistrationJournal {
  static let service = "com.skworks.sko.qr-scanner.pending.v1"
  static func account(_ actor: String, _ company: String) throws -> String {
    guard SKOQRKeyScope.validUUID(actor), SKOQRKeyScope.validUUID(company) else { throw SKOQRKeyError.unavailable }
    return SHA256.hash(data: Data("sko.qr.scanner.pending.v1\n\(actor)\n\(company)".utf8)).map { String(format: "%02x", $0) }.joined()
  }
  static func query(_ account: String) -> [String: Any] {
    [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:account,
     kSecAttrSynchronizable as String:false,kSecUseDataProtectionKeychain as String:true]
  }
  private static func data(_ account: String) throws -> Data? {
    var q = query(account); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
    let context = LAContext(); context.interactionNotAllowed = true; q[kSecUseAuthenticationContext as String] = context
    var result: CFTypeRef?; let status = SecItemCopyMatching(q as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let bytes = result as? Data, bytes.count <= 8192 else { throw SKOQRKeyError.unavailable }
    return bytes
  }
  private static func object(_ bytes: Data) throws -> [String: Any] {
    guard let value = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { throw SKOQRKeyError.unavailable }; return value
  }
  static func read(actor: String, company: String, session: String) throws -> [String: Any]? {
    let root = try account(actor,company), marker = try data(root + ".marker"), pending = try data(root + ".record")
    if marker == nil && pending == nil { return nil }
    guard let marker, let pending else { throw SKOQRKeyError.unavailable }
    let m = try object(marker), p = try object(pending)
    guard m.count == 5, m["actor"] as? String == actor, m["company"] as? String == company, m["session"] as? String == session,
      p["nonce"] as? String == m["nonce"] as? String, p["device"] as? String == m["device"] as? String else { throw SKOQRKeyError.unavailable }
    try validate(p,actor:actor,company:company,session:session); return p
  }
  private static func add(_ account: String, _ value: [String: Any]) throws {
    var q = query(account); q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
    q[kSecValueData as String] = try JSONSerialization.data(withJSONObject:value,options:[.sortedKeys])
    guard SecItemAdd(q as CFDictionary,nil) == errSecSuccess else { throw SKOQRKeyError.unavailable }
  }
  // Explicit NEW logical device setup only, after fresh local user presence.
  // Never called automatically because read() is absent/failed. Any existing or
  // ambiguous custody key blocks initialization rather than replacing it.
  static func create(actor: String, company: String, session: String) throws -> [String: Any] {
    let root = try account(actor,company)
    guard SKOQRKeyScope.validUUID(session), try data(root + ".marker") == nil, try data(root + ".record") == nil else { throw SKOQRKeyError.unavailable }
    var keys: [String: Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:SKOQRScannerKeyCustody.service,
      kSecAttrSynchronizable as String:false,kSecUseDataProtectionKeychain as String:true,kSecReturnAttributes as String:true,kSecMatchLimit as String:kSecMatchLimitAll]
    let context = LAContext(); context.interactionNotAllowed = true; keys[kSecUseAuthenticationContext as String] = context
    var existing: CFTypeRef?
    guard SecItemCopyMatching(keys as CFDictionary,&existing) == errSecItemNotFound else { throw SKOQRKeyError.unavailable }
    let device = UUID().uuidString.lowercased(), nonce = UUID().uuidString.lowercased()
    let scope = try SKOQRKeyScope(actor:actor,company:company,device:device)
    let marker: [String: Any] = ["actor":actor,"company":company,"session":session,"device":device,"nonce":nonce]
    let pending: [String: Any] = ["schema":1,"actor":actor,"company":company,"session":session,"device":device,"handle":scope.handle,"nonce":nonce,
      "version":0,"stage":"key_pending","publicKeyHex":NSNull(),"challenge":NSNull(),"challengeRequestId":NSNull(),
      "proofRequestIds":[String](),"completionRequestId":NSNull(),"registrationEventId":NSNull()]
    // Marker first. A crash between these ACKs is a blocked recovery state, not
    // permission to generate another identity. No erase/overwrite API exists.
    try add(root + ".marker",marker); try add(root + ".record",pending)
    guard let result = try read(actor:actor,company:company,session:session), NSDictionary(dictionary:result).isEqual(to:pending) else { throw SKOQRKeyError.unavailable }
    return result
  }
  private static func integer(_ value: Any?) -> Int64? {
    guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite,
      n.doubleValue.rounded() == n.doubleValue, n.doubleValue >= 0, n.doubleValue <= 9007199254740991 else { return nil }; return n.int64Value
  }
  static func validate(_ p: [String: Any],actor: String,company: String,session: String) throws {
    let fields: Set<String> = ["schema","actor","company","session","device","handle","nonce","version","stage","publicKeyHex","challenge","challengeRequestId","proofRequestIds","completionRequestId","registrationEventId"]
    guard Set(p.keys) == fields, integer(p["schema"]) == 1, p["actor"] as? String == actor,p["company"] as? String == company,
      p["session"] as? String == session, SKOQRKeyScope.validUUID(session), let device = p["device"] as? String,
      let nonce = p["nonce"] as? String, SKOQRKeyScope.validUUID(nonce), integer(p["version"]) != nil,
      let stage = p["stage"] as? String, ["key_pending","key_ready","challenge_sent","challenge_ready","proof_sent","proof_rejected","proof_delivered","proof_lost","completion_sent","confirmed"].contains(stage),
      let attempts = p["proofRequestIds"] as? [String], attempts.count <= 5, Set(attempts).count == attempts.count, attempts.allSatisfy(SKOQRKeyScope.validUUID),
      p["handle"] as? String == (try SKOQRKeyScope(actor:actor,company:company,device:device)).handle else { throw SKOQRKeyError.unavailable }
    for name in ["challengeRequestId","completionRequestId"] {
      guard p[name] is NSNull || (p[name] as? String).map(SKOQRKeyScope.validUUID) == true else { throw SKOQRKeyError.unavailable }
    }
    if stage == "key_pending" { guard p["publicKeyHex"] is NSNull else { throw SKOQRKeyError.unavailable } }
    else { guard let key = p["publicKeyHex"] as? String, key.range(of:"^302a300506032b6570032100[0-9a-f]{64}$",options:.regularExpression) != nil else { throw SKOQRKeyError.unavailable } }
    if let c = p["challenge"] as? [String: Any], let key = p["publicKeyHex"] as? String {
      _ = try SKOQRScannerKeyCustody.signingBytes(c,scope:SKOQRKeyScope(actor:actor,company:company,device:device),session:session,publicKey:key)
    } else if !(p["challenge"] is NSNull) { throw SKOQRKeyError.unavailable }
    let hasChallenge = p["challenge"] is [String: Any], hasRequest = p["challengeRequestId"] is String
    let beforeChallenge = ["key_pending","key_ready"].contains(stage)
    guard hasRequest == !beforeChallenge, hasChallenge == !["key_pending","key_ready","challenge_sent"].contains(stage),
      attempts.isEmpty == ["key_pending","key_ready","challenge_sent","challenge_ready"].contains(stage),
      (p["completionRequestId"] is String) == ["completion_sent","confirmed"].contains(stage),
      (p["registrationEventId"] is String) == (stage == "confirmed") else { throw SKOQRKeyError.unavailable }
    if let event = p["registrationEventId"] as? String { guard let n = UInt64(event), n > 0, n <= UInt64(Int64.max), String(n) == event else { throw SKOQRKeyError.unavailable } }
    else if !(p["registrationEventId"] is NSNull) { throw SKOQRKeyError.unavailable }
  }
  static func transition(_ original: [String: Any],actor: String,company: String,session: String,expectedVersion: Int64,next: String,patch: [String: Any]) throws -> [String: Any] {
    try validate(original,actor:actor,company:company,session:session)
    var current = original
    guard integer(current["version"]) == expectedVersion,let stage = current["stage"] as? String,expectedVersion < 9007199254740991 else { throw SKOQRKeyError.unavailable }
    let rules: [String: [String: Set<String>]] = [
      "key_pending":["key_ready":["publicKeyHex"]],"key_ready":["challenge_sent":["challengeRequestId"]],
      "challenge_sent":["challenge_ready":["challenge"]],"challenge_ready":["proof_sent":["proofRequestId"]],
      "proof_rejected":["proof_sent":["proofRequestId"]],"proof_sent":["proof_rejected":[],"proof_delivered":[],"proof_lost":[]],
      "proof_delivered":["completion_sent":["completionRequestId"],"proof_lost":[]],"completion_sent":["confirmed":["registrationEventId"]]]
    guard let fields = rules[stage]?[next], Set(patch.keys) == fields else { throw SKOQRKeyError.unavailable }
    for (key,value) in patch {
      if key == "proofRequestId" {
        guard let id = value as? String,SKOQRKeyScope.validUUID(id),var attempts = current["proofRequestIds"] as? [String],attempts.count < 5,!attempts.contains(id) else { throw SKOQRKeyError.unavailable }
        attempts.append(id);current["proofRequestIds"] = attempts
      } else { current[key] = value }
    }
    current["stage"] = next;current["version"] = expectedVersion + 1
    try validate(current,actor:actor,company:company,session:session)
    return current
  }
  static func advance(actor: String,company: String,session: String,expectedVersion: Int64,next: String,patch: [String: Any]) throws -> [String: Any] {
    guard let old = try read(actor:actor,company:company,session:session) else { throw SKOQRKeyError.unavailable }
    let current = try transition(old,actor:actor,company:company,session:session,expectedVersion:expectedVersion,next:next,patch:patch)
    let bytes = try JSONSerialization.data(withJSONObject:current,options:[.sortedKeys]);guard bytes.count <= 8192 else { throw SKOQRKeyError.unavailable }
    let root = try account(actor,company)
    // All channel calls are serialized on the app main queue. This read/update
    // is not a cross-process CAS, OS transaction, or physical-device attestation.
    guard SecItemUpdate(query(root + ".record") as CFDictionary,[kSecValueData as String:bytes] as CFDictionary) == errSecSuccess,
      let result = try read(actor:actor,company:company,session:session),NSDictionary(dictionary:result).isEqual(to:current) else { throw SKOQRKeyError.unavailable }
    return result
  }
}

#if canImport(Flutter) && canImport(UIKit)
import Flutter
import UIKit
final class SKOQRRegistrationJournalChannel {
  private let channel: FlutterMethodChannel
  private var context: LAContext?
  private var pendingID: String?
  private var pendingResult: FlutterResult?
  private var timeout: DispatchWorkItem?
  private var observer: NSObjectProtocol?
  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name:"com.skworks.sko/qr_scanner_pending",binaryMessenger:messenger)
    channel.setMethodCallHandler { [weak self] call,result in DispatchQueue.main.async {
      guard let self else { result(FlutterError(code:"unavailable",message:"元の登録手続きを確認できません。",details:nil));return }
      self.handle(call,result:result)
    }}
    observer = NotificationCenter.default.addObserver(forName:UIApplication.didEnterBackgroundNotification,object:nil,queue:.main) { [weak self] _ in self?.cancel() }
  }
  private func cancel() {
    context?.invalidate();context=nil;timeout?.cancel();timeout=nil;pendingID=nil
    let result=pendingResult;pendingResult=nil;result?(FlutterError(code:"unavailable",message:"元の登録手続きを確認できません。",details:nil))
  }
  private func handle(_ call: FlutterMethodCall,result: @escaping FlutterResult) {
    guard let args=call.arguments as? [String:Any],let id=args["requestId"] as? String,SKOQRKeyScope.validUUID(id) else {
      result(FlutterError(code:"unavailable",message:"元の登録手続きを確認できません。",details:nil));return
    }
    if call.method == "cancel" { if pendingID == id { cancel();result(true) } else { result(false) };return }
    guard pendingID == nil,Bundle.main.object(forInfoDictionaryKey:"SKOQRScannerKeyPreparationEnabled") as? Bool == true,
      UIApplication.shared.applicationState == .active,let actor=args["actor"] as? String,let company=args["company"] as? String,
      let session=args["session"] as? String,SKOQRKeyScope.validUUID(actor),SKOQRKeyScope.validUUID(company),SKOQRKeyScope.validUUID(session) else {
      result(FlutterError(code:"unavailable",message:"スキャナー登録は準備中です。",details:nil));return
    }
    do {
      if call.method == "read",args.count == 4 {
        if let pending=try SKOQRRegistrationJournal.read(actor:actor,company:company,session:session) { result(["status":"found","pending":pending]) }
        else { result(["status":"absent"]) };return
      }
      if call.method == "advance",args.count == 7,let version=args["expectedVersion"] as? NSNumber,
        CFGetTypeID(version) != CFBooleanGetTypeID(),version.doubleValue.rounded() == version.doubleValue,
        let next=args["nextStage"] as? String,let patch=args["patch"] as? [String:Any] {
        result(try SKOQRRegistrationJournal.advance(actor:actor,company:company,session:session,expectedVersion:version.int64Value,next:next,patch:patch));return
      }
      guard call.method == "createNewLogicalDeviceIntent",args.count == 4 else { throw SKOQRKeyError.unavailable }
      let auth=LAContext(),started=ProcessInfo.processInfo.systemUptime
      auth.touchIDAuthenticationAllowableReuseDuration=0;context=auth;pendingID=id;pendingResult=result
      let expiry=DispatchWorkItem { [weak self] in if self?.pendingID == id { self?.cancel() } };timeout=expiry
      DispatchQueue.main.asyncAfter(deadline:.now()+90,execute:expiry)
      auth.evaluatePolicy(.deviceOwnerAuthentication,localizedReason:"新しい論理スキャナーの登録手続きを開始します。") { [weak self] ok,_ in DispatchQueue.main.async {
        guard let self,self.pendingID == id else { return }
        guard ok,UIApplication.shared.applicationState == .active,ProcessInfo.processInfo.systemUptime-started<90 else { self.cancel();return }
        do {
          let pending=try SKOQRRegistrationJournal.create(actor:actor,company:company,session:session)
          guard self.pendingID == id,UIApplication.shared.applicationState == .active,ProcessInfo.processInfo.systemUptime-started<90 else { self.cancel();return }
          self.context?.invalidate();self.context=nil;self.timeout?.cancel();self.timeout=nil;self.pendingID=nil
          let callback=self.pendingResult;self.pendingResult=nil;callback?(pending)
        } catch { self.cancel() }
      }}
    } catch { result(FlutterError(code:"unavailable",message:"元の登録手続きを確認できません。",details:nil)) }
  }
  deinit { context?.invalidate();timeout?.cancel();if let observer { NotificationCenter.default.removeObserver(observer) } }
}
#endif
