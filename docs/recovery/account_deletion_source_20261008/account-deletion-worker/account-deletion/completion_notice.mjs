// Server-only. The RPC supplies a previously verified recipient, never the client.
// A reserved-but-unconfirmed delivery requires reconciliation, not blind retries.
export function createCompletionNotice({rpc, send, renew}) {
  if (![rpc,send,renew].every(f=>typeof f==='function')) throw Error('incomplete_completion_notice');
  return async job => {
    const args={p_id:job.id,p_lease:job.leaseToken};
    const notice=await rpc('reserve_account_deletion_notice',args);
    if(notice?.state==='sent') return true;
    if(notice?.state!=='reserved' || notice.requestId!==job.id ||
       typeof notice.recipient!=='string' || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(notice.recipient)) {
      throw Error('completion_notice_unavailable');
    }
    if(await renew(job)!==true) throw Error('lease_lost');
    let receipt;
    try {
      receipt=await send({to:notice.recipient,idempotencyKey:`account-deletion/${job.id}`,
        subject:'【SKO】アカウント削除完了のお知らせ',
        text:'SKOのアカウント削除が完了しました。会社に必要な給与・請求・署名済み日報などの記録は、ご案内した方針に従って保持されます。\nお問い合わせ: sko.support@gmail.com'});
    } catch (_) { throw Error('completion_delivery_unconfirmed'); }
    if(typeof receipt?.id!=='string' || !/^[A-Za-z0-9_-]{1,200}$/.test(receipt.id)) throw Error('completion_delivery_unconfirmed');
    if(await renew(job)!==true) throw Error('lease_lost');
    return await rpc('confirm_account_deletion_notice',{...args,p_receipt:receipt.id})===true;
  };
}
