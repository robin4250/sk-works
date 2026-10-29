import Foundation
import CryptoKit
import Security
import LocalAuthentication

func hex(_ s: String) -> Data { Data(stride(from: 0, to: s.count, by: 2).map { i in UInt8(s.dropFirst(i).prefix(2), radix: 16)! }) }
func require(_ ok: @autoclosure () -> Bool, _ label: String) { if !ok() { fatalError(label) } }
let seed = hex("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60")
let key = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
require(key.publicKey.rawRepresentation == hex("d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"), "RFC8032 public key")
let emptySignature = try key.signature(for: Data())
require(key.publicKey.isValidSignature(hex("e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b"), for: Data()), "RFC8032 signature verification")
require(key.publicKey.isValidSignature(emptySignature, for: Data()), "actual randomized CryptoKit signature")
require(!key.publicKey.isValidSignature(emptySignature, for: Data([1])), "mutated data rejected")
let actor = "00000000-0000-4000-8000-000000000001", company = "00000000-0000-4000-8000-000000000002", device = "00000000-0000-4000-8000-000000000003", sid = "00000000-0000-4000-8000-000000000004"
let scope = try SKOQRKeyScope(actor: actor, company: company, device: device)
let pub = SKOQRScannerKeyCustody.spki(key.publicKey)
let challenge: [String: Any] = ["id": actor, "company": company, "actor": actor, "session": sid, "device": device, "nonce": sid, "keyHex": pub, "createdMs": 1000, "expiresMs": 2000, "databaseNowMs": 1500]
let bytes = try SKOQRScannerKeyCustody.signingBytes(challenge, scope: scope, session: sid, publicKey: pub)
let interopSignature = try key.signature(for: bytes)
let interop = try JSONSerialization.data(withJSONObject: ["publicKeyHex": pub, "bytes": bytes.base64EncodedString(), "signature": interopSignature.base64EncodedString()], options: [.sortedKeys])
print("QR_INTEROP " + String(data: interop, encoding: .utf8)!)
let expected = "[\"sko.qr.scanner.register.key-possession.v1\",\"\(actor)\",\"\(company)\",\"\(actor)\",\"\(sid)\",\"\(device)\",\"\(pub)\",\"\(sid)\",1000,2000]"
require(String(data: bytes, encoding: .utf8) == expected, "actual server canonical signing bytes")
for mutation in [["actor": company], ["session": actor], ["keyHex": "00"], ["createdMs": true], ["expiresMs": 1000], ["databaseNowMs": 2000], ["unexpected": 1]] as [[String: Any]] {
  do { _ = try SKOQRScannerKeyCustody.signingBytes(challenge.merging(mutation) { _, v in v }, scope: scope, session: sid, publicKey: pub); fatalError("accepted invalid challenge") } catch {}
}
let other = try SKOQRKeyScope(actor: company, company: company, device: device)
require(scope.handle != other.handle, "scope handle separates actor")
print("PASS actual CryptoKit RFC8032 and exact server registration signing bytes; actor/SID/key/schema/time mutation denied")

// Actual Security.framework calls, no fake Keychain or user-presence success.
// The unique synthetic account never refers to a user's stored app item.
let isolated = try SKOQRKeyScope(actor: actor, company: company, device: UUID().uuidString.lowercased())
var add = SKOQRScannerKeyCustody.query(isolated)
require(add[kSecAttrSynchronizable as String] as? Bool == false, "non synchronizing")
require(add[kSecUseDataProtectionKeychain as String] as? Bool == true, "data protection keychain")
add[kSecAttrAccessControl as String] = try SKOQRScannerKeyCustody.accessControl()
add[kSecValueData as String] = key.rawRepresentation
let added = SecItemAdd(add as CFDictionary, nil)
if added == errSecSuccess {
  defer { SecItemDelete(SKOQRScannerKeyCustody.query(isolated) as CFDictionary) }
  let context = LAContext(); context.interactionNotAllowed = true
  var query = SKOQRScannerKeyCustody.query(isolated)
  query[kSecReturnData as String] = true; query[kSecUseAuthenticationContext as String] = context
  var result: CFTypeRef?
  let denied = SecItemCopyMatching(query as CFDictionary, &result)
  require(denied != errSecSuccess && result == nil, "actual protected Keychain forbids no-presence read")
  do { _ = try SKOQRScannerKeyCustody.sign(isolated, session: sid, handle: isolated.handle, challenge: challenge, context: context); fatalError("signed without user presence") } catch {}
  print("PASS actual protected Keychain insert and no-UI retrieval/sign rejection; synthetic item removed")
} else {
  require([errSecMissingEntitlement, errSecNotAvailable, errSecAuthFailed, errSecInteractionNotAllowed].contains(added), "unexpected Keychain insertion error: \(added)")
  print("LIMIT actual protected Keychain insert denied by hosted process (status \(added)); no downgrade or signing success claimed")
}
print("LIMIT physical passcode/biometry/user-presence success, restart custody and signed iPhone Keychain remain unverified")
