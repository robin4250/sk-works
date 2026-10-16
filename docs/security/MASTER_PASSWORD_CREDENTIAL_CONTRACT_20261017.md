# Master-only password: isolated contract candidate

## Status and ownership

Review-only, default OFF, not a migration or production application. User superseded the shared-OR proposal: PR1168 is preserved on HOLD and is not this design. Existing Master role IDs, company memberships, providers, primary credentials, shared-secondary hashes, UI routes and server operation proofs are not migrated or rewritten. Auth writer owns this new SQL/doc; separate owners add only new setup/change UI and isolated server tests. Stage2 existing-gate wiring is pending.

Current source has no dedicated Master password store/setup/change. MasterProtectedPage currently verifies the shared secondary password and Face plus trusted Master device. Master roles are already separate in private.master_admins. The new password does not grant Master status: all methods require existing enabled Master, current allowed account/live nonanonymous session, and this actor's already trusted unlocked/unrevoked device. First trusted-device bootstrap/recovery is not a password-reset authorization channel.

## Explicit OFF and rollout

New private.master_password_settings starts enabled=false; candidate reruns do not change an existing value. No public setter is provided. New master_password_capability returns {protocol,enabled} only for existing allowed Master; others get denied. Other new methods return disabled when explicitly OFF. Existing source remains unchanged. Future gate must distinguish explicit OFF old-source compatibility from ON unknown API/network/permission failures, which must fail closed without shared-secondary fallback. Production enable requires the user's separate backup/restore/admin-preservation/isolated-test/impact approval conditions.

## Exact wire contract

All replies have protocol="sko-master-password-v1". Errors have exactly {protocol,status}; status is denied,disabled,invalid,expired,conflict,not_verified,locked. No internal SQL exception, raw UID, session, device key, secret or hash is returned. Transport/permission errors are failures and must not trigger another authentication route.

| RPC / arguments | Successful fields in addition to protocol |
|---|---|
| master_password_capability() | enabled:boolean (no status on success) |
| current_master_password_status(p_device_key:text) | status:ready, configured:boolean, credential_version:integer (0 if absent) |
| begin_master_password_operation(p_device_key:text,p_operation:text,p_expected_version:bigint,p_request_id:uuid) | status:challenge, operation, expected_version, request_id, challenge_id:uuid, nonce:64 lowercase hex, expires_at:UTC timestamp |
| complete_master_password_operation(p_device_key:text,p_challenge_id:uuid,p_nonce:text,p_existing_password:text,p_new_password:text,p_request_id:uuid) | status:applied, operation:setup/change, request_id, credential_version:expected+1, configured:true |
| verify_master_password_operation(p_device_key:text,p_challenge_id:uuid,p_nonce:text,p_password:text,p_request_id:uuid) | status:verified, operation:unlock, request_id, credential_version:expected (unchanged), configured:true |
| read_master_password_request(p_device_key:text,p_request_id:uuid) | status:found, request_id, result:original applied/verified reply; or status:not_found,request_id without result |

Operations: setup requires no dedicated credential and expected_version=0; change/unlock require an existing credential and its exact version. Setup's existing_password is the actor's existing shared-secondary secret, verified by the existing server verify_secondary_password inside the same transaction. Change/unlock verify the independent dedicated Master hash. No local Face boolean or caller-supplied role is accepted by SQL. Master Face remains additional native confirmation in future gate (AND), never shared-OR bypass.

## Atomic state machine and failures

Begin creates a random 256-bit nonce. Only its SHA256 is stored; this is a random challenge digest, never a password digest. Bind actor + original server session_id + trusted device row + operation + expected credential version + request UUID. TTL exactly 120 seconds. New state is in private.master_password_credentials/challenges/attempts/requests; no anonymous or authenticated direct table CRUD or helper execute grants. Public new RPC execute is authenticated only, with authoritative server checks inside.

Complete/verify serializes on the existing Master actor row, checks own live session/account/device, locks its own dedicated credential and nonce, consumes nonce once, verifies the actual secret server-side, then performs set-once INSERT/change CAS/unlock. Setup and change invalidate all remaining new Master-password challenges for this actor. No transferable proof is returned: verified is a receipt of that one operation, not a reusable server authorization token. Existing primary-operation proof tables are unchanged.

Wrong secrets increment the new Master-specific failure counter and return a generic response rather than raise/rollback. Five failed submissions lock new operations for five minutes. At most five live unconsumed challenges per actor. Setup calls the existing secondary verifier; its normal successful/failed verification counter/timestamp side effects are intentional, but its password hash and all other actors remain unchanged. Existing secondary lock/errors map to generic failed verification; no reset or overwrite of that credential.

Passwords: new secret at least 8 characters and at most 72 UTF8 bytes (bcrypt limit); existing secret nonempty and at most 72 UTF8 bytes. No trim/normalization. Dedicated bcrypt salt cost12 is newly generated: shared hashes are not copied or moved. Separate stores remain separate even if a user types the same value. Password equality is not used to infer roles or account linking.

All new operations use existing deletion advisory barrier plus account_access_allowed, auth.users allowed/not anonymous, auth.sessions same actor/not expired, enabled Master and own trusted device row checks/locks; time-based session expiry is rechecked after waiting. Trusted device_key is a bearer secret, not hardware attestation. Native Face is an additional client check, not server proof.

## Unknown commit, privacy and receipts

Client saves only nonsecret operation metadata before complete: actor/session/device fingerprint, request UUID, operation/version/challenge ID. Never persist nonce, passwords, auth tokens, raw device key or password SHA. Unknown completion must not be resubmitted. Receipt read is bound to the same current actor/session/trusted device and reveals only success metadata. not_found is an observation, not proof of failure; a transaction may still complete. After logout/session replacement, do not infer another session's request result or resend secrets. No secret-bearing payload fingerprint is stored. A consumed nonce cannot be replayed with a changed password; duplicate complete returns conflict, and only receipt read resolves success.

PostgREST/log infrastructure must not log request bodies or SQL bind parameters containing secrets. This SQL adds no secret logs/audit payloads; the isolated signed-REST fixture is not proof of production gateway/log configuration. That configuration and native real-device behavior remain unverified rollout blockers.

## Required tests before adoption

- DefaultOFF and authenticated company admin/submanager/viewer/general/anonymous denial; another Master cannot target another actor (no actor argument).
- Live session/account/master/device revocation and lock-wait rechecks; nonce TTL/replay/wrong session/device/operation/version/request rejection.
- Actual shared-secondary secret setup, dedicated salted hash only; one concurrent setup winner; setup cannot overwrite after configuration.
- Dedicated old-secret change/unlock, wrong secret lock counter persistence, concurrent version-CAS one winner, old challenges invalidated.
- Direct private-table/helper access denied; response/receipt JSON contains no secrets/hash/nonce outside initial challenge.
- Original Auth ID/providers/role/company/secondary hash and other users unchanged; only expected secondary verification counters/timestamps may change.
- Current gate/normal settings unchanged until new tests and independent review succeed; staged wiring must keep ON errors fail closed and Master Face AND dedicated password.

## Recovery and rollback limits

There is no new Master-password-forgot/reset method in this candidate. Existing dual-email device recovery is not repurposed to reset this password. Before ON, an approved independent reset/recovery policy and isolation tests are required to avoid lockout. Disabling candidate mode is an operator change requiring approval, not a client fallback. Do not delete or roll back production credential state without the required safe backup/restoration process. Review-only SQL is not proof that any production backup/restore or account recovery succeeded.
