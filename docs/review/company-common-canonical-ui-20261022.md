# Canonical common payroll UI foundation

Prepared against main `6ffaf7d4adec9a63805fc1acb094d9cbc97b5308`.
This is an **unwired client candidate**, not a completed payroll rollout.
No existing panel, repository, salary calculation, common card, help, translation,
role, database or network endpoint is changed by these new files.

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

The immutable command matches the backend agent's draft v2 publish parameter
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
capability; then add a gated v2 repository and reuse the existing publication
panel's type/month controls. Persist the exact approved command **before** its
first network call. On unknown outcome, restore the matching pending command and
offer read-only receipt verification only. Map verified results and unresolved
reasons to the existing common-card contract. Update root-owned help/translations
when the UI is actually connected. Real JWT/RLS/proxy, native concurrency,
screen/PDF/print/share and administrator iPhone checks remain unfinished.
