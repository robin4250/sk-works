# Expected-company linkage qualification candidate

The client sends the selected own company to each linkage operation and rejects stale actor/session/company results. It pins the captured bearer for dispatch. A selector is required for multiple eligible companies.

forward.stopped.sql is a review artifact, not an automatic migration. It intentionally aborts. It changes the legacy selector to allow only one membership and adds twelve functions (one scoped helper, five private and five public overloads, one context RPC), with explicit execution ACLs. The old single-company RPC argument shapes are retained. Existing rows, settings, notifications and link states are not changed by installing these definitions.

The updated client depends on those RPCs and fails closed while absent. Do not deploy the server artifact or enable new capabilities from this file. Production application needs an exact current-catalog check and separate explicit approval under the existing change instructions. The historical first-company selector is not an automatic rollback because restoring it restores the ambiguity.

Qualification: six Dart cases and changed-file analysis; nine isolated PostgreSQL groups; three isolated real GoTrue/PostgREST/SDK cases. The real SDK dispatch check switches users while the request is held and verifies only the captured actor is mutated, then stale results are rejected. Synthetic users/companies only; all sessions and containers were cleaned. Edge runtime, full production role/trigger closure and owner-device UI remain separate.
