# Security review — 2026-10-26 handoff

Baseline: `robin4250/sk-works` main `22ba6ec4349c66a14244fc76f0e823a0831ae142`. Source/canonical catalogue inspection only; no real-user authentication, production writes, provider/Auth setting changes, or local Flutter/Dart commands.

## Client candidate

Draft PR https://github.com/robin4250/sk-works/pull/1421 binds secondary reset verification through save to actual auth event history and SDK session_id. A→B→A, same-user new session and sign-out invalidate verification; same-session JWT refresh remains valid. A captured token pins the legacy save RPC. The isolated primary verifier requires a distinct temporary SID and never logs out an unexpectedly reused original SID. This does not add server enforcement to legacy RPCs.

## Confirmed remaining server boundary

Authenticated callers can invoke the existing `set_secondary_password(text)` to overwrite their own secondary credential using only a bearer token. The current body does not require old-secondary/primary proof or check a live session. The existing `verify_secondary_password(text)` returns a boolean; attendance management RPC authorization validates role/company/live session but consumes no secondary-success receipt.

The staged `tool/staged/reauthentication_proofs.sql`, `supabase/functions/reauthenticate-operation/handler.mjs`, and existing operation repository are the single candidate protocol. Catalogue checks show their proof/rollout tables, capability/proof RPCs and Edge are absent from the live deployment. Do not label absent modules as deployed-but-OFF or activate client requirements before server readiness.

## Smallest review and deployment plan

1. Reuse the staged SQL/Edge/client candidate; retain default-OFF rollout. Review its upgrade/restore transaction and dependency order separately from this client change.
2. Confirm first-time credential setup is preserved while legacy existing-credential overwrite is blocked when proof enforcement is enabled. A server-wide activation must not strand OAuth-only Google/Face ID users; the password-only staged proof does not solve their recovery.
3. In an isolated Native fixture, verify anonymous, foreign user/company, wrong operation/target/SID, expired/consumed nonce and rolled-back consumption are rejected. Verify exact same actor+SID succeeds once; a new SID and revoked original session fail. Use the existing proof tests, adding only uncovered paths.
4. Test legacy overwrite closure and first setup separately. Preserve all existing user/company/identity IDs and real credentials/signatures. Do not test destructive overwrite against a production account.
5. For attendance step-up, design a server-issued current-session/action/target receipt using the existing proof model; an app navigation password or native Face ID result alone is not server evidence.
6. Read-only Auth settings review is still required for leaked-password protection and Apple provider/manual-link/signup guard. Current MCP metadata did not expose these settings; no inferred configuration changes were made.

## Related allowance preservation finding

The inspected live `force_manage_attendance` implementation deletes and reinserts worker rows without `company_allowance_selections` / `company_allowance_legacy_labels`. The before-state audit is retained but does not preserve current typed values. Parent owns the fix: keep registered IDs/name snapshots/version/unit and free labels distinct, and add a focused unrelated-time-edit preservation regression. No production row was mutated to demonstrate this.

`source-pins.json` and `findings.json` contain privacy-safe source/catalogue evidence without real user/company IDs, credentials, tokens or keys. CI status for the draft client candidate must be checked independently; no main merge or production rollout is authorized by a green isolated candidate alone.
