import AuthenticationServices
import CryptoKit
import Security
import UIKit

final class SKOAppleCredentialSource: NSObject,
  ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
  private let anchor: UIWindow
  private var controller: ASAuthorizationController?
  private var pending: ((Result<SKOAppleCredential, SKOAppleCredentialError>) -> Void)?
  private var rawNonce: String?
  private var expectedState: String?

  init(anchor: UIWindow) { self.anchor = anchor; super.init() }

  // Retain this object until completion. The caller owns actor/session-history validation.
  func request(completion: @escaping (Result<SKOAppleCredential, SKOAppleCredentialError>) -> Void) {
    dispatchPrecondition(condition: .onQueue(.main))
    guard pending == nil else { completion(.failure(.busy)); return }
    guard let nonce = randomValue(), let state = randomValue() else {
      completion(.failure(.unavailable)); return
    }
    let request = ASAuthorizationAppleIDProvider().createRequest()
    request.requestedScopes = []
    request.nonce = SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
    request.state = state
    rawNonce = nonce; expectedState = state; pending = completion
    let operation = ASAuthorizationController(authorizationRequests: [request])
    controller = operation
    operation.delegate = self
    operation.presentationContextProvider = self
    operation.performRequests()
  }

  func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor { anchor }

  func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
    guard controller === self.controller else { return }
    guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
      let nonce = rawNonce, let expected = expectedState, credential.state == expected,
      let bytes = credential.identityToken, bytes.count <= 16384,
      let token = String(data: bytes, encoding: .utf8), !token.isEmpty else {
      finish(.failure(.unavailable)); return
    }
    finish(.success(SKOAppleCredential(idToken: token, rawNonce: nonce)))
  }

  func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
    guard controller === self.controller else { return }
    let cancelled = (error as? ASAuthorizationError)?.code == .canceled
    finish(.failure(cancelled ? .cancelled : .unavailable))
  }

  func cancel() {
    dispatchPrecondition(condition: .onQueue(.main))
    let operation = controller
    finish(.failure(.cancelled))
    if #available(iOS 16.0, *) { operation?.cancel() }
  }

  private func finish(_ result: Result<SKOAppleCredential, SKOAppleCredentialError>) {
    let callback = pending
    pending = nil; rawNonce = nil; expectedState = nil
    controller?.delegate = nil; controller?.presentationContextProvider = nil; controller = nil
    callback?(result)
  }

  private func randomValue() -> String? {
    var bytes = [UInt8](repeating: 0, count: 32)
    let status = bytes.withUnsafeMutableBytes { buffer in
      SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
    }
    guard status == errSecSuccess else { return nil }
    return Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
  }
}

#if canImport(Flutter)
import Flutter

final class SKOAppleCredentialChannel {
  private let channel: FlutterMethodChannel
  private let state = SKOAppleCredentialRequestState()
  private var source: SKOAppleCredentialSource?
  private var backgroundObserver: NSObjectProtocol?
  private var timeout: DispatchWorkItem?
  private let enabled: () -> Bool
  init(messenger: FlutterBinaryMessenger, enabled: @escaping () -> Bool = {
    Bundle.main.object(forInfoDictionaryKey: "SKOAppleCredentialPreparationEnabled") as? Bool == true
  }) {
    self.enabled = enabled
    channel = FlutterMethodChannel(name: "com.skworks.sko/apple_credential", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { result(FlutterError(code: "disposed", message: "Appleの本人確認は準備中です。", details: nil)); return }
      DispatchQueue.main.async { self.handle(call, result) }
    }
    backgroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
      self?.cancelCurrent()
    }
  }
  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard call.method == "requestAppleCredential" || call.method == "cancelAppleCredential" else { result(FlutterMethodNotImplemented); return }
    guard let args = call.arguments as? [String: Any], args.count == 1, let id = args["request_id"] as? String,
      SKOAppleCredentialRequestState.validID(id) else {
      result(FlutterError(code: "invalid_request", message: "Appleの本人確認を開始できません。", details: nil)); return
    }
    if call.method == "cancelAppleCredential" {
      guard state.requestID == id else { result(false); return }
      cancelCurrent(); result(true); return
    }
    guard enabled(), UIApplication.shared.applicationState == .active,
      let anchor = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap({ $0.windows }).first(where: { $0.isKeyWindow }) else {
      result(FlutterError(code: "unavailable", message: "Appleによるログインは準備中です。", details: nil)); return
    }
    do {
      try state.begin(id: id, enabled: true, now: ProcessInfo.processInfo.systemUptime) { value in
        switch value {
        case .success(let credential): result(["id_token": credential.idToken, "nonce": credential.rawNonce])
        case .failure(let error):
          let code: String
          switch error { case .busy: code = "busy"; case .cancelled: code = "cancelled"; case .unavailable: code = "unavailable" }
          result(FlutterError(code: code, message: "Appleの本人確認を完了できませんでした。", details: nil))
        }
      }
    } catch {
      result(FlutterError(code: "busy", message: "Appleの本人確認を進めています。", details: nil)); return
    }
    let operation = SKOAppleCredentialSource(anchor: anchor)
    source = operation
    let timer = DispatchWorkItem { [weak self] in self?.cancelCurrent() }
    timeout = timer; DispatchQueue.main.asyncAfter(deadline: .now() + 180, execute: timer)
    operation.request { [weak self, weak operation] value in
      guard let self, self.source === operation else { return }
      self.timeout?.cancel(); self.timeout = nil; self.source = nil
      guard UIApplication.shared.applicationState != .background else {
        self.state.finish(id: id, value: .failure(.cancelled), now: ProcessInfo.processInfo.systemUptime); return
      }
      self.state.finish(id: id, value: value, now: ProcessInfo.processInfo.systemUptime)
    }
  }
  private func cancelCurrent() {
    guard let id = state.requestID else { return }
    timeout?.cancel(); timeout = nil
    state.finish(id: id, value: .failure(.cancelled), now: ProcessInfo.processInfo.systemUptime)
    let current = source; source = nil; current?.cancel()
  }
  deinit {
    timeout?.cancel(); channel.setMethodCallHandler(nil)
    if let observer = backgroundObserver { NotificationCenter.default.removeObserver(observer) }
  }
}
#endif
