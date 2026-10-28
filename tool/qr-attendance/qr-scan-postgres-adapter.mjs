// Internal candidate. Hooks are trusted database-only application adapters, NOT
// request parameters. No subject impersonation or production writer is provided.
export function createQrScanPostgresAdapter({pool, initializeVerifiedSession,
  loadLockedScan, writeRegularAttendance, consumeWithReceipt}) {
  const hooks={initializeVerifiedSession,loadLockedScan,writeRegularAttendance,consumeWithReceipt};
  if (typeof pool?.connect!=='function'||Object.values(hooks).some(h=>typeof h!=='function')) throw new TypeError('trusted QR database hooks required');
  return {async runLockedTransaction(run) {
    const client=await pool.connect();let started=false,discarded=false;
    try {
      await client.query('begin isolation level serializable');started=true;
      await client.query("set local lock_timeout='2s';set local statement_timeout='5s';set local idle_in_transaction_session_timeout='5s'");
      // This hook validates the already-authenticated request in the transaction;
      // it must not take user_metadata as authority or mint a subject identity.
      await initializeVerifiedSession(client);
      await client.query('select qr_attendance_private.require_enabled()');
      const result=await run({
        loadLockedScan:args=>loadLockedScan(client,args),
        writeRegularAttendance:args=>writeRegularAttendance(client,args),
        consumeWithReceipt:args=>consumeWithReceipt(client,args),
      });
      await client.query('commit');started=false;return result;
    } catch(error) {
      if(started){try{await client.query('rollback');}catch{discarded=true;client.release(true);throw error;}}
      throw error;
    } finally {
      // pg release after a successful rollback clears transaction-local claims.
      // The caller may retry serialization failures explicitly using the same QR.
      if(!discarded) client.release();
    }
  }};
}
