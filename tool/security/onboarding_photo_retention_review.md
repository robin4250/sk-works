# Review-only onboarding photo-reference preservation candidate

Depends on #1139 catalog/35-check baseline. No production apply, UI edits, RLS
changes, Auth settings, provider updates or PII-column grants. Supabase CLI was
unavailable in the editing runtime; SQL remains `.sql.review-only` outside normal
migrations and must not be copied into a deployment queue automatically.

## Precisely limited changes

The existing deployed `public.save_employee_onboarding_profile(10 text)` source
is copied exactly and changes ONLY removal of three SET assignments that forced
portrait/my-number paths to NULL. Existing required text validation, photo-path
rejection during beta, actor/readiness/status logic, notification payload,
signature and ACL remain. No new uploads are enabled. A new user's NULL paths
stay NULL; existing paths are never written by this RPC. A later photo-reference
change between a capability read and submit is also retained because those
columns are absent from UPDATE SET. This is not a general text-field CAS change.

An exact original source MD5, signature, SECURITY DEFINER/search_path/volatility,
return type, postgres owner and existing EXECUTE ACL guard stops drift. MD5 is a
definition-comparison guard, not cryptographic authentication. CREATE OR REPLACE
preserves the original function OID and ACL. Guard mismatch requires independent
review; there is no force-overwrite path.

New public invoker `employee_onboarding_photo_capability()` calls only a new
private STABLE SD implementation, with empty search_path and authenticated-only
EXECUTE. It accepts NO actor/company/invite parameter. The current actor must
pass account access and own the latest eligible onboarding invite, with the same
password-change OR identity-verification readiness. The JSON contains exactly
two booleans: `has_existing_images` and `photo_upload_allowed:false`. It returns
no path, image, company/user/invite ID, contact detail, count or session metadata.
It never mutates invite state. Private schema usage is an existing prerequisite;
no new table or column grant is added. This is not an OAuth/session-revocation
change, and stale-but-unexpired JWT behavior follows the existing account gate.

The fixed upload flag reflects the guarded paused-beta contract. A future photo
rollout requires independent coordinated review; this candidate does not discover
or activate arbitrary Storage permission changes. UI work remains deferred until
server retention/capability contracts are reviewed and safely available.

## Candidate-only verification

The new fixture reuses #1139's captured definitions rather than reimplementing
the completed 35-case Storage baseline. PGlite reproduces original RPC legacy
path clearing within a rolled-back transaction, then checks candidate legacy
three-path preservation, new NULL-path success, boolean-only/read-only capability,
anonymous/no-invite/restricted-account denial, identity-verification readiness,
interleaved reference update preservation, photo-upload pause, exact source-only
diff, OID/ACL retention, drift rejection, late DDL rollback and exact original
source/data/role restoration. Notification transport is a synthetic sink only.

Dedicated CLI2.121.0 CI starts a NEW empty temp local Auth/Data-API stack (Storage
is excluded). Real GoTrue-issued sessions check only the new candidate delta:
legacy/new submission, safe capability, invalid actor override/private endpoint,
account guard, no PII grants, signature/OID/ACL preservation, original source and
synthetic invite/company-owner/Auth-ID restoration. No actual Storage or provider
E2E equivalence is claimed. All tokens, fixture identities and paths remain in
private memory/temp files; only fixed classifications are printed. Cleanup stops
only this temp project and deletes its volumes.

Protected production backup, tested restoration, existing administrator identity
and permissions, Apple/Google flows, and the user's explicit final approval are
required before any production permission/auth/data-contract change. This PR
does not perform that approval-dependent operation or modify the current UI.
