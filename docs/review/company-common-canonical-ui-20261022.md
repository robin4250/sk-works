# Canonical common payroll UI foundation

Prepared against main `6ffaf7d4adec9a63805fc1acb094d9cbc97b5308`.
This is a **client candidate**, not a completed payroll rollout. The existing
registration page is connected through a contract-3 capability-gated publication
surface. The older unsafe contract is rejected and the backend itself must be
reviewed and deployed before rollout. An optional backward-compatible common-card
reason projection is also included. No salary calculation, help, translation,
role or database is changed by this client candidate.

## Files to stage onto the reviewed main tree

- `lib/features/payroll/company_common_canonical_publication_command.dart`
- `lib/features/payroll/company_common_canonical_publication_pending_store.dart`
- `lib/features/payroll/company_common_canonical_publication_approval.dart`
- `test/company_common_canonical_publication_pending_test.dart`
- `test/company_common_canonical_publication_approval_test.dart`

The independent candidate checkout also contains five baseline files for source
inspection. Those baseline files are unchanged and **must not** be submitted as
new changes or replace newer upstream edits.

Remote verification command, after staging the five files in the complete
Flutter 3.47.5 repository with the existing lockfile:

```sh
flutter test test/company_common_canonical_publication_pending_test.dart test/company_common_canonical_publication_approval_test.dart
```

Local Flutter/Dart execution was not performed. `git diff --check` succeeded.
The tests remain unexecuted until the integration owner's remote CI runs them.

## Command and recovery boundary

The immutable command matches the backend agent's contract-3 publish parameter
names. It retains the original company/source/timeline versions, exact original
request ID, preview token, individual reconciliation rule and each legacy
identity/generation/selection basis. No aliases or quantities are inferred.
The command rejects extra parameter keys, unsupported quantity basis, duplicate
identities and credential-bearing JSON keys. A later server contract change must
be reflected explicitly in this parser; it is not silently accepted.

Pending records have their own command kind, schema and private support-folder
namespace, separate from existing company-setting save records. They contain no
access/refresh token and no current session. The actor and company are checked
before and after asynchronous file operations. Atomic-write recovery, matching
payload-only clear, corrupted/ambiguous record retention, concurrent write
serialization and cross-account separation are covered by candidate tests.

An unknown publish result remains pending across app recreation. Read-only receipt
lookup uses the same `p_expected_command` and request ID. A missing receipt must
not trigger automatic resubmission or generation of another request ID. This
foundation does not itself call either publish or receipt lookup.

## Approval UI boundary

The dialog shows target/excluded/unresolved counts, with detailed reasons
initially folded. It requires separate explicit first-activation consent and
selected-day quantity consent when relevant. Unresolved, invalid, preparation-only
or undeployed previews cannot be confirmed. Deployment availability defaults to
false. A replaced preview clears previous consent.

The existing payroll authorization must protect all preview data before mapping
it into this view model. This widget is not an authorization boundary. No new
salary reader may expose amounts or worker scopes to attendance-only proxies.

## Next integration work

Finalize and validate backend preview/receipt response keys and deployment
capability; then add a gated canonical repository and reuse the existing publication
panel's type/month controls. Persist the exact approved command **before** its
first network call. On unknown outcome, restore the matching pending command and
offer read-only receipt verification only. Map verified results and unresolved
reasons to the existing common-card contract. Update root-owned help/translations
when the UI is actually connected. Real JWT/RLS/proxy, native concurrency,
screen/PDF/print/share and administrator iPhone checks remain unfinished.

## Versioned repository and one-attempt controller

The additional candidate files are
`company_common_canonical_publication_repository.dart`,
`company_common_canonical_publication_controller.dart` and
`test/company_common_canonical_publication_repository_test.dart` in the existing
payroll/test directories. Add the last test to the remote command above.

The Supabase repository requires an integer `3` from the read-only
`company_common_payroll_publication_v2_contract_version` probe under the current
session before any canonical preview, publish or receipt call. Returned command, company,
timeline, target/excluded/unresolved counts and readback evidence are validated.
The controller persists before its sole publish call. A PostgreSQL rejection of
that first attempt clears only the identical command after confirmed rollback.
Transport/session/parse failures remain unknown and keep the pending record.
Restored requests can only query the read-only receipt endpoint; missing receipts
or receipt permission errors never clear or resend a command. Candidate tests
exercise the real Supabase SDK against a synthetic HTTP transport plus actual
temporary files for lost-result/recreation and known-rejection behavior.

These tests have not been run locally. The repository follows the existing pinned
Dart SDK `.rpc(..., params: ...)`/authorization-header usage; official Dart RPC
documentation was checked. The markdown changelog index could not be retrieved
by the documentation browser because of its unsupported content type; this code
does not change the SDK dependency version or use a new SDK feature.

## Activation contract correction

The first publisher draft used company-wide activation and could stop an unrelated payroll type. It is rejected by this client: capability and response contract must be integer 3. RPC names still end in `_v2`; the confirmed publish command now includes `p_activation_scope`. Preview must distinguish `payroll_type`/`per_type` from existing `legacy_company`/`legacy_global`. A legacy-company initial activation is never approved by this client. Approval wording names the selected payroll type. The pending command kind, schema and private folder are version 3; draft version-2 records are neither accepted nor silently migrated. No version-2 client was shipped by this candidate. Backend contract/activation changes must finish before rollout.

## Connected panel and real SQL response conformance

The further UI files are `company_common_canonical_publication_panel.dart` and
`company_common_payroll_publication_surface.dart`; the existing
`company_common_payroll_page.dart` header is changed only to pass the saved state
through that surface. Registration and salary application remain separate.
The surface never swaps a live older publication panel due to a background
version probe. When positive legacy slots exist and contract 3 is unavailable,
registration remains available but the older apply action is not offered.

The connected panel loads a matching durable pending record before allowing a
new approval. It shows target/excluded/unresolved counts, requires positive
selected-day and initial selected-payroll-type consent, and retains uncertain
results for read-only lookup. A resume while a publish is in flight drains the
original attempt, reloads its record and never issues another publish. A second
confirmation callback cannot pop the underlying page or send another command.
Historical publication entries remain visible after reopening. Future start
months are bounded to the server's current-month through next-12-month range.

Add `test/company_common_canonical_publication_panel_test.dart` to the remote
test invocation, and stage its support helper
`test/support/common_canonical_client_fixture.dart`. Those are synthetic client
behavior fixtures. Separately, the repository tests consume the actual synthetic
SQL export at `test/fixtures/company_common_canonical_publication_contract3.json`,
copied unchanged from backend commit `60aef6c`. They validate company-state to
preview-parameter equivalence, preview approval, committed receipt command,
publish readback and read-only receipt parsing, both directly and through the
real Supabase SDK using only a synthetic HTTP transport. This is not a real-token
or production-app authorization test.

The common card retains registered display units for inherited legacy items and
shows that unselected days are zero, rather than relabeling all quantities as
ordinary working days. All candidate Flutter tests still require remote execution.
