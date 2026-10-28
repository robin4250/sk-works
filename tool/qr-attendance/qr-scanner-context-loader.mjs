// Internal database-only loader. Inputs are the locked server ledger scope.
export async function loadQrScannerContext(client,{actor,session,lockedChallenge}) {
 const r=await client.query('select qr_attendance_private.load_scanner_context($1,$2,$3,$4) as context',
  [lockedChallenge.companyId,lockedChallenge.deviceId,lockedChallenge.subjectWorkerId,lockedChallenge.subjectUserId]);
 const value=r.rows[0]?.context;
 if(!value||value.actor!==actor||value.session!==session||typeof value.publicKeyHex!=='string'||
   !/^302a300506032b6570032100[a-f0-9]{64}$/.test(value.publicKeyHex))return null;
 return {...value,publicKeyDer:Buffer.from(value.publicKeyHex,'hex')};
}
