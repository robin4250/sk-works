// Internal candidate only. Actor/session come from verified server authentication.
// The authorization context and existing regular attendance writer remain trusted
// application adapters, never callbacks or identifiers supplied by an HTTP body.
export function createQrScanLedgerHooks({actor,session,loadAuthorizedContext}) {
  const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  if(!uuid.test(actor)||!uuid.test(session)||typeof loadAuthorizedContext!=='function')throw TypeError('trusted QR request context required');
  actor=actor.toLowerCase();session=session.toLowerCase();
  return {
    async loadLockedScan(client,request) {
      if(request.actor!==actor||request.session!==session)return null;
      const result=await client.query(`select *,
        floor(extract(epoch from clock_timestamp())*1000)::bigint as now_ms,
        floor(extract(epoch from expires_at)*1000)::bigint as expires_ms
        from qr_attendance_private.scan_challenges
        where id=$1 and scanner_actor=$2 and scanner_session=$3 for update`,[request.challengeId,actor,session]);
      const row=result.rows[0];if(!row)return null;
      // Snapshot immutable scope before awaiting context I/O.
      const lockedChallenge=Object.freeze({companyId:row.company_id,deviceId:row.device_id,
        challengeId:row.id,tokenHash:row.token_hash,action:row.action,sourceClockInId:row.source_clock_in_id,
        subjectWorkerId:row.subject_worker_id,subjectUserId:row.subject_user_id});
      const authority=await loadAuthorizedContext(client,{actor,session,lockedChallenge});
      if(!authority)return null;
      return {...authority,actor,session,challenge:lockedChallenge,
        nowMs:Number(row.now_ms),expiresMs:Number(row.expires_ms),
        consumed:row.receipt_id!==null,receiptId:row.receipt_id};
    },
    async consumeWithReceipt(client,{challengeId,receiptId}) {
      const result=await client.query(`update qr_attendance_private.scan_challenges
        set receipt_id=$2,consumed_at=clock_timestamp()
        where id=$1 and scanner_actor=$3 and scanner_session=$4
          and receipt_id is null and expires_at>clock_timestamp() returning id`,
      [challengeId,receiptId,actor,session]);
      return result.rowCount===1;
    },
  };
}
