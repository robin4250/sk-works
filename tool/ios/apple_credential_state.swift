import Foundation

struct SKOAppleCredential { let idToken: String; let rawNonce: String }
enum SKOAppleCredentialError: Error { case busy, cancelled, unavailable }

// Correlation and exactly-once delivery only, never an authentication decision.
final class SKOAppleCredentialRequestState {
  private(set) var requestID: String?
  private var started: TimeInterval = 0
  static func validID(_ id: String) -> Bool {
    let bytes = Array(id.utf8)
    return (16...80).contains(bytes.count) && bytes.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 }
  }
  private var deadline: TimeInterval = 0
  private var completion: ((Result<SKOAppleCredential, SKOAppleCredentialError>) -> Void)?
  func begin(id: String, enabled: Bool, now: TimeInterval,
    completion: @escaping (Result<SKOAppleCredential, SKOAppleCredentialError>) -> Void) throws {
    guard enabled, now.isFinite, Self.validID(id) else {
      throw SKOAppleCredentialError.unavailable
    }
    guard requestID == nil else { throw SKOAppleCredentialError.busy }
    requestID = id; started = now; deadline = now + 180; self.completion = completion
  }
  @discardableResult func finish(id: String, value: Result<SKOAppleCredential, SKOAppleCredentialError>, now: TimeInterval) -> Bool {
    guard requestID == id else { return false }
    let callback = completion
    let valid = now.isFinite && now >= started && now < deadline
    requestID = nil; started = 0; deadline = 0; completion = nil
    callback?(valid ? value : .failure(.unavailable))
    return true
  }
}
