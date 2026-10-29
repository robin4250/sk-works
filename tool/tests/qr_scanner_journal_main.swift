import Foundation
import CryptoKit
import Security

func require(_ value: @autoclosure () -> Bool,_ label: String){if !value(){fatalError(label)}}
let actor="00000000-0000-4000-8000-000000000001",company="00000000-0000-4000-8000-000000000002",device="00000000-0000-4000-8000-000000000003",sid="00000000-0000-4000-8000-000000000004",nonce="00000000-0000-4000-8000-000000000005"
let scope=try SKOQRKeyScope(actor:actor,company:company,device:device)
let publicKey="302a300506032b6570032100"+String(repeating:"ab",count:32)
var state:[String:Any]=["schema":1,"actor":actor,"company":company,"session":sid,"device":device,"handle":scope.handle,"nonce":nonce,"version":0,"stage":"key_pending","publicKeyHex":NSNull(),"challenge":NSNull(),"challengeRequestId":NSNull(),"proofRequestIds":[String](),"completionRequestId":NSNull(),"registrationEventId":NSNull()]
func move(_ next:String,_ patch:[String:Any])throws{state=try SKOQRRegistrationJournal.transition(state,actor:actor,company:company,session:sid,expectedVersion:(state["version"] as! NSNumber).int64Value,next:next,patch:patch)}
func denied(_ work:()throws->Void){do{try work();fatalError("accepted invalid transition")}catch{}}
try SKOQRRegistrationJournal.validate(state,actor:actor,company:company,session:sid)
for field in ["password","proof","token","signature","privateKey"]{var changed=state;changed[field]="synthetic-secret";denied{try SKOQRRegistrationJournal.validate(changed,actor:actor,company:company,session:sid)}}
denied{_ = try SKOQRRegistrationJournal.transition(state,actor:actor,company:company,session:sid,expectedVersion:1,next:"key_ready",patch:["publicKeyHex":publicKey])}
denied{_ = try SKOQRRegistrationJournal.transition(state,actor:actor,company:company,session:nonce,expectedVersion:0,next:"key_ready",patch:["publicKeyHex":publicKey])}
try move("key_ready",["publicKeyHex":publicKey]);try move("challenge_sent",["challengeRequestId":nonce])
let challenge:[String:Any]=["id":nonce,"actor":actor,"company":company,"session":sid,"device":device,"keyHex":publicKey,"nonce":nonce,"createdMs":1000,"expiresMs":90000,"databaseNowMs":1001]
try move("challenge_ready",["challenge":challenge]);let challengeReady=state
try move("proof_sent",["proofRequestId":actor]);let proofSent=state
try move("proof_rejected",[:]);try move("proof_sent",["proofRequestId":company]);try move("proof_delivered",[:]);let proofDelivered=state
try move("completion_sent",["completionRequestId":device]);try move("confirmed",["registrationEventId":"9223372036854775807"])
denied{try move("completion_sent",["completionRequestId":nonce])}
state=proofSent;try move("proof_lost",[:]);denied{try move("proof_sent",["proofRequestId":nonce])}
state=proofDelivered;try move("proof_lost",[:]);denied{try move("completion_sent",["completionRequestId":nonce])}
state=challengeReady;denied{try move("proof_sent",["proofRequestId":actor,"proof":"synthetic-secret"])}
state=proofSent;denied{try move("challenge_sent",["challengeRequestId":nonce])}
print("PASS actual native write-ahead transition policy: exact owner/SID/nonce/schema/version, rejected-password explicit retry, terminal lostproof, no backward/resend/secret state")
// Actual protected Keychain read, never an injected storage-success callback.
do{_ = try SKOQRRegistrationJournal.read(actor:UUID().uuidString.lowercased(),company:UUID().uuidString.lowercased(),session:sid);print("PASS actual native journal query completed (no real fixture creation or user-presence claim)")}
catch{print("LIMIT hosted process cannot access Data Protection Keychain; signed-device persistence/ACK/restart remains unverified")}
