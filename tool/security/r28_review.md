# R28 isolated review candidate — protected request staging

Status: review only, no production changes, no deploy/migration hook. Five new files only; payroll/calculation source and ordinary submission function unchanged. Production schema/function/policy/trigger/FK metadata was read; no business rows or credentials were retrieved.

## Evidence and change

The exact original private LINE attendance wrapper invokes the exact ordinary past-attendance submission function, which creates a request, items and company-assignee notifications before durable private LINE lineage is inserted. The fixture reproduces one notification to a non-Master assignee before the candidate and zero afterwards. A private transaction/backend-bound call context is created only by the Master-only LINE wrapper after original validation. A new BEFORE request INSERT trigger binds the generated request UUID to the already-validated actor/company before any notice is enqueued. The existing R19 request classifier and R20 notification classifier recognize only that transaction/backend pending context plus durable lineage. Completion requires durable lineage, then context is deleted in the same transaction. Every SQL statement remains inside the original transaction.

The ordinary submit_past_attendance_request source MD5 remains `3b8a6b1d701c110910f8f6c0cc6bd0db`; amount/time/worker/site calculation and item JSON construction are unchanged. Existing constraints/FKs remain unchanged. Ordinary no-context request INSERT returns NEW immediately even if Master detection returns NULL. No GUC/title/user metadata is used as authorization; JWT settings in the fixture simulate authenticated PostgREST claims only.

Restrictive ALL request/item policies add defense in depth. Exact existing permissive policy overlay tests establish that parent SELECT already blocks non-Master insert/reparent into known LINE drafts; this is not reported as a newly discovered existing direct-write bypass. Ordinary own draft writes remain allowed and managers with attendance feature disabled remain denied.

## Verification

Local PGlite chain: R28 47 checks; R19–27 full prior chain retained. Cases include original source hashes, reproduction/fix of notification timing, unchanged ordinary notification with Master helper NULL, linked direct write/reparent rejection under actual policy definitions, ordinary editing, role/feature denial, Master NULL, private table client CRUD denial, different backend context non-capture, each nullable request binding field rejection, injected item failure whole operation rollback and next-command success, idempotence, unchanged item numeric values, late source drift rollback removing newly-created context objects. Actual PG17/PostgREST workflow is included; its result must be recorded separately before approval.

## Restore and production gates

Fixture restores exact prior source definitions and removes the new trigger/policies/function/table, leaving previous chain checks passing. Candidate dynamically verifies source hashes, owners, security-definer/search-path and preserves OID/owner/ACL/config on replacement. A source-drift failure rolls back all new DDL. This is not full production backup restoration.

The global BEFORE request trigger is explicitly NOT production authorized. Before production: save full current schema/ACL/Auth/admin/company settings; verified isolated restoration; latest actual catalog comparison and complete trigger inventory; administrator and normal-user UI comparison; explain impact and obtain explicit approval. No deployment or remote data writes occurred.

## Unconfirmed and limits

Real GoTrue/provider sessions, iPhone UI, full live RLS policy inventory and Storage are not covered. Private LINE draft/access helpers remain explicit synthetic fixtures inherited from R25. Master-private approval workflow is unspecified: this candidate prevents ordinary company notification/publication but does not invent private approval/self-approval. Old already-created notices/caches/external copies are neither deleted nor revoked. Unknown provenance/copied records cannot be classified automatically. Existing R22 candidate seals Master approval into ordinary attendance; ordinary calculation source is untouched. Transaction backend isolation is tested with a mismatched backend ID locally; actual concurrent backend races remain unverified. Full security/TestFlight readiness is not claimed.
