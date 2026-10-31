# Preserve retirement status in the existing worker binding

Status: source review and isolated validation only. **Production HOLD; deployable:false.**

The bounded production catalog read found public.ensure_current_user_worker() with definition MD5 `10565c7d5a53e45f37a4c6be0f58b538`. It is owned by postgres, SECURITY DEFINER, search_path public/pg_temp, with postgres/authenticated/service_role EXECUTE. No private function with the same name was present and this body does not delegate to another worker-binding helper. No business rows were read and the function was not called in production.

The observed existing-worker branch unconditionally writes status=active. Current qualification and attendance clients call this RPC to obtain their own worker ID, so an existing inactive worker can be reactivated by that read-oriented entry path. PR1710 fixes a different Edge invitation path and does not fix this function.

The minimal proposed change removes only the existing-worker status assignment. It preserves the UUID return contract for active and inactive workers, the existing name/phone behavior, company selection, authentication check, owner/ACL/security/search_path/OID, and new-worker active creation. It does not delete an account, ban login to other companies, change historical originals, alter payroll, create a retirement date, or implement reinstatement.

The isolated repair requires the exact observed definition and protection attributes and derives the new body by replacing one exact fragment. Unknown drift aborts. It deliberately refuses any database except the synthetic `retirement_fixture`; this is not a production installer.

## Remaining production conditions

* Approval must identify this function/body change separately from UI1712 and invitation1710.
* Refresh the bounded catalog and caller inventory; do not silently rebaseline drift.
* A safe admission stop and drain of already-running old function frames has not been proven. CREATE OR REPLACE alone must not be claimed to cancel an old call already executing. Prepared/cached/in-flight behavior needs independent Native two-connection verification and an approved cutover plan.
* No grant/RLS expansion or global Auth redesign is proposed. Existing consumers that use an inactive UUID for archived records must remain readable under their existing authorization.
* After rollout, independently read the exact body/owner/ACL/config and verify the old existing-worker status assignment is absent. Do not invoke the function against a real retired employee as a test.
* Do not restore the old body after use: that would reintroduce reactivation. A stop must preserve worker rows and history. A reviewed forward stop/drain/repair plan is still required; no destructive rollback is included.

## Other retirement work, separate from this candidate

The current retirement page stores status=inactive, not a retirement date/reason/event ledger. An explicit effective-date/reason/audit design requires a separate approved schema proposal. Reinstatement and switching to a subcontractor are distinct administrator actions and must never happen as a side effect of login, invitation or a document screen.

Past payroll, attendance, qualifications and signatures must remain stored. Historical selectors and new-work selectors need separate review: current attendance management filters active workers; the attendance-sheet employee picker excludes inactive workers for all months. Qualification management can read worker status including inactive; qualification recognition selects active only. These differences are not all defects, and must not be flattened into one global active filter.
