import Foundation
var checks = 0
func check(_ value: Bool) { precondition(value); checks += 1 }
let state = SKOAppleCredentialRequestState()
let id = String(repeating: "a", count: 32), other = String(repeating: "b", count: 32)
let credential = SKOAppleCredential(idToken: "synthetic.token.only", rawNonce: String(repeating: "n", count: 43))
var deliveries = 0, successes = 0, failures = 0
let callback: (Result<SKOAppleCredential, SKOAppleCredentialError>) -> Void = { value in
  deliveries += 1
  switch value { case .success: successes += 1; case .failure: failures += 1 }
}
for enabled in [false] {
  do { try state.begin(id: id, enabled: enabled, now: 1, completion: callback); preconditionFailure() }
  catch { check(state.requestID == nil) }
}
for invalid in ["short", String(repeating: "x", count: 81), id + "\n"] {
  do { try state.begin(id: invalid, enabled: true, now: 1, completion: callback); preconditionFailure() }
  catch { check(state.requestID == nil) }
}
try state.begin(id: id, enabled: true, now: 1, completion: callback)
do { try state.begin(id: other, enabled: true, now: 2, completion: callback); preconditionFailure() }
catch { check(state.requestID == id) }
check(!state.finish(id: other, value: .success(credential), now: 2))
check(deliveries == 0)
check(state.finish(id: id, value: .failure(.cancelled), now: 2))
check(deliveries == 1 && failures == 1 && successes == 0)
check(!state.finish(id: id, value: .success(credential), now: 3))
try state.begin(id: other, enabled: true, now: 10, completion: callback)
check(!state.finish(id: id, value: .success(credential), now: 11))
check(state.finish(id: other, value: .success(credential), now: 12))
check(deliveries == 2 && successes == 1 && state.requestID == nil)
try state.begin(id: id, enabled: true, now: 20, completion: callback)
check(state.finish(id: id, value: .success(credential), now: 200))
check(deliveries == 3 && successes == 1 && failures == 2)
try state.begin(id: id, enabled: true, now: 30, completion: callback)
check(state.finish(id: id, value: .success(credential), now: .nan))
check(failures == 3)
print("Apple credential state: \(checks) checks passed; no Auth calls")
