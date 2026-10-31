# Qualification intent file journal successor (source only)

Fixed parent: PR1701 at9ef6140aa1efae4a23eb6447521c07dd4fffcf20. The parent source and its54 tests/independent review stay frozen.

The parent writes intents through SharedPreferences. A successful setString/reload is not sufficient evidence of a flushed restart-recovery record. This successor switches the live port to a qualification-only ApplicationSupport file journal following the existing pending-file pattern. Shared stores, Auth, SQL and original photos remain unchanged.

A scoped, hashed key identifies one actor/company/qualification. Files carry a versioned key/value/checksum envelope; the intent identity and selection cannot be overwritten by another request ID. Writes take the local queue/native file lock, claim a unique temporary name, recheck current contents, flush, read back, rename atomically, and read back again before returning to the RPC caller. A valid sole first-write temporary record is decoded and flushed before restart recovery; conflicting current+temporary records remain a manual-review hold, never silently discarded. Symlinks, corrupt/oversized or cross-scope files fail closed. Legacy preference records are not ignored or deleted; their presence holds new writes for explicit reconciliation/migration.

Acknowledgement can remove the active pointer only when the independently confirmed final receipt was archived with the exact same immutable request context. The archive remains. SDK/session/target scope is checked around file IO. No tokens or image bytes are persisted. The parent in-process command exclusion and server request UUID are retained.

Tests use generated private temporary directories only. Include fault after flush before rename (RPC not dispatched), actual file-backed unknown submit followed by new repository/SID get-only recovery, immutable-ID competition, checksum corruption, symlink namespace rejection, legacy hold and archived-terminal clear. The actual SDK/host test reads the flushed file from the prepare interceptor before accepting the request.

This is a process/restart file-recovery guarantee within the tested app flow, not a hardware power-loss, all-filesystem or cross-device/isolated-writer proof. Directory fsync/OS failure, full at-rest security, multi-isolate and native process scheduling are not claimed. A conflicting replacement temporary file deliberately requires manual reconciliation. No production/Storage API/private images/featureON/main merge/Release/device action occurs.
