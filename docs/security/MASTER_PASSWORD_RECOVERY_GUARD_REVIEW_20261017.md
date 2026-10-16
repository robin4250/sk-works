# Master-password recovery and preservation review — 2026-10-17

Independent read-only review of PR1170 exact `9fb2cab01fff6e1de34587214297d176bec2000f`, specifically `tool/staged/master_password_credentials.sql.review-only` and its separate contract. This document owns no authentication implementation. No production SELECT, real account/device/provider values, secret or hash values, credentials, role changes or SQL execution were used for this review. Source-review findings are not runtime proof.

## Preservation findings

| Existing state | Candidate behavior | Protection still required |
|---|---|---|
| private.master_admins IDs/enabled state | Existing actor row is checked/locked, not inserted, changed or deleted. New tables reference it; credentials do not grant Master role. | Preserve actual original IDs/enabled state and compare in protected isolation. Do not recreate or delete the Master row to repair password setup. |
| company_members and company association | No writes in this candidate | Compare protected company membership/roles after restoration and before/after rollout. |
| Auth users/sessions/provider/primary password | Existing user/session checked and share-locked; no Auth update/reset/provider migration | Preserve Apple/Google and primary login; native/device test remains separate. |
| Shared-secondary password hash | Not copied, moved or updated by the candidate. Setup invokes existing server verifier. | The existing verifier's normal success/failure counters and timestamps can change; verify actual hash and unrelated actors stay unchanged. Do not pretend setup has zero secondary-state side effects. |
| Master devices | Existing own trusted, unlocked, unrevoked device checked/locked; no registration/recovery changes | Preserve bootstrap/dual-email device recovery; neither is a dedicated-password reset authorization channel. |
| Existing operation proofs | Unchanged; new verified reply is one operation's receipt, not a transferable proof | Future gate must not replace existing server action proofs with a local boolean or this receipt. |
| Existing routes/gates | Candidate does not wire routes or edit the old gate | Current source compatibility is separate from the pending dedicated gate implementation. |

New state is limited to five private tables: settings, credentials, attempts, challenges, requests, plus new functions. Credential is independent salted bcrypt cost12, bound to existing Master ID/version. Challenge is 120 seconds, single-use, tied to actor/session/device/operation/version/request. Completion rechecks time/context after crypt work, invalidates remaining challenges after setup/change and records nonsecret success metadata atomically. These are source observations; the PG17/REST/concurrency owner must establish their runtime behavior.

## OFF, ON failure, and recovery must remain different

- Initial enabled=false; no public setter. Reapplying the candidate does not reset an existing flag. The flag is operator-controlled state, not a recovery button.
- Explicit authenticated capability OFF can retain the previously approved old gate. Missing RPC, denied access, unknown response, timeout or transport error is not explicit OFF and must not cause fallback when ON.
- The existing gate remains unchanged until a separately reviewed Stage2. The intended ON gate is native Face AND dedicated Master password, without shared-secondary OR fallback. Source-only setup does not establish this gate.
- No dedicated forgot/reset recovery exists. Before ON, approve and isolate-test a recovery policy that does not trust a local biometric success, device recovery alone, an arbitrary company admin, or a client-provided verification flag to reset this credential.
- Approved operator OFF may be an emergency compatibility action, with a documented security tradeoff. It is not an automatic client response to an error. Test that OFF does not delete credentials, lower versions or alter existing Master identity, company or secondary data.
- Existing account login recovery and user-confirmed access do not prove dedicated-password recovery.

## Rollback hazards and safe boundaries

Dropping the new tables or restoring an older credential snapshot can remove configured state, revive an old dedicated password, lower versions, allow setup again, or mismatch receipts/challenges. Do not call this a harmless rollback. New credential state must be retained when withdrawing only an unconnected UI/source candidate.

A source rollback is also distinct from a database rollback: removing functions while ON and leaving a wired client causes fail-closed lockout. Removing new functions or downgrading the API must therefore be excluded from an ON rollout until an approved coordinated operator/client recovery sequence has been tested. Prefer forward repair with preserved state over ad-hoc table deletion; no automated rollback SQL is supplied or authorized here.

Restoring new challenge/request tables must not revive usable pre-restoration nonces. Establish a tested invalidation/epoch or equivalent policy before rollout; do not invent it during an incident. Original operation-proof and session state must be evaluated consistently. Restoring an old hash/version while leaving newer receipts or cached successful UI state is unsafe.

Foreign keys use ON DELETE CASCADE from the existing Master ID to new state. That does not modify the old ID, but deleting/recreating an existing Master registration would destroy the new credential/recovery history. Such deletion is forbidden as a repair step.

## Required protected backup and isolation evidence

| Item | Status at review | Requirement |
|---|---|---|
| Exact candidate SQL/contract and this review | Source saved | Pin SHA; later edits need re-review |
| New credential/challenge runtime and race/REST tests | Separate owner in progress | Review exact successful head; do not infer success from source |
| Existing protected production backup | Not obtained in this lane | Original full DDL/ACL/security metadata, original Auth/provider/master/device/company/role settings and required business data, privately stored |
| New credential/attempt/challenge/request/settings backup | Not obtained; production candidate not applied | Treat bcrypt hashes and nonce digests as secrets; never Git, chat logs, screenshots or per-account public checksums |
| Restoration from protected real backup | Not verified | Disposable isolated environment, outbound mail/SMS/provider/notifications disabled; internal identity/role/company/provider comparisons without exposing values |
| New forgotten-password recovery / approved OFF operation | Not implemented/approved here | Policy, authorization/audit, failure and recovery test before ON |
| Production gateway/SQL-bind request-body logging | Not verified | Secret-bearing calls must not persist request bodies/passwords/nonces/device keys |
| Existing administrator/UI/native provider comparison | Not verified here | Compare working old gate and normal settings plus intended new path on actual release/device |
| Production change/enable approval | Not obtained | User's existing six protection conditions remain mandatory |

An anonymous fixture with sentinel identities is useful but cannot establish restoration of actual production administrator accounts. Metadata hashes alone are not restorable definitions or a full backup. A complete restored account/provider state is not safe to publish; compare it only inside the protected operator workflow.

## Concrete independent acceptance checks

1. Prove old gate/normal settings unchanged with flag OFF, no new RPC, and no route connected; separately reject ON missing/permission/network failures without shared fallback.
2. Rehearse setup/change/unlock failure rollback at each write boundary. Preserve old Master ID, roles, company, Auth providers and secondary hash; allow only documented secondary-verification counter changes.
3. Prove one setup winner, version-CAS race, post-lock and post-bcrypt expiry, session/device/Master revocation, nonce replay and cross-actor request collisions. Failures must not expose SQL internals or secrets.
4. Resolve unknown commit only by same-context receipt; not_found is unresolved. Never resend passwords/nonces. Restart-safe nonsecret journaling is being added separately; memory-only initial UI head fe03a6c is insufficient evidence for restart retention.
5. Prove background/route/actor/session/device changes erase secrets and reject late UI success. Nonsecret unresolved metadata must not be overwritten, misattributed or cleared by another actor; exact committed success may clear only its own request.
6. Before ON, demonstrate dedicated-password loss recovery, protected restore, operator OFF, re-enable and API downgrade/withdrawal sequence without losing existing Master administration. No production enable until this passes and impact approval is obtained.

No production apply/enable, backup, reset, restore or deployment authorization is granted by this document. The candidate remains default OFF/review-only; Stage2 gate, real recovery policy, production backup/restore and real-device validation are not complete.
