# Limited payroll access-checkpoint verification

The single-draft candidates in PRs #1256/#1257 previously used simplified account/feature predicates in the shared fixture. This new local-only PGlite verifier accepts an explicit trusted private catalog checkpoint, installs five access predicates in a disposable fixture and compares nine direct helper bodies, security-definer flags, volatility and search paths with that checkpoint.

It does not connect to production, accept a database URL/native adapter, deploy functions, or print the checkpoint. The private input contains definitions/metadata only and is not included in Git. No actual employee, company, salary, role-membership rows, JWT, or credentials are supplied to the fixture. The test uses existing synthetic payroll data and existing reviewed calculators.

## Run

Run from the repository root with an absolute pinned PGlite module and trusted private checkpoint:

```sh
node tool/verify_payroll_access_checkpoint.mjs /absolute/node_modules/@electric-sql/pglite/dist/index.js /absolute/private_checkpoint.json
```

Input format is `sko-payroll-helper-checkpoint-v1` with exactly the nine signatures listed by the script. Do not obtain this input from an untrusted party: five definitions are executed inside the disposable PGlite database. The script does not replay captured production grants or ownership.

## Executed locally

- All nine direct helper bodies/security attributes matched the limited read-only catalog checkpoint.
- Owner and explicit payroll editor could preview. Viewer, manager without a payroll grant, and anonymous actors were refused.
- A manager required an explicit company payroll-feature or payroll-edit grant. Revocation refused access without altering the draft.
- The account-deletion restriction predicate refused both preview and apply; removing the synthetic restriction permitted preview again.
- An approved professional invite with view access did not become edit access.
- The salary row stayed unchanged through these checks. No successful apply/recalculation is performed by this verifier.

## Limits

Minimal synthetic tables supply the columns read by these predicates; they do not reproduce all real constraints/policies. Old fixture helpers are renamed before installing the checkpoint predicates to preserve existing fixture object dependencies. Existing RLS policies can remain bound to old fixture function OIDs: this is a test of the new preview/apply entry predicates, not proof of all RLS paths. Auth.uid still uses a synthetic setting, not a real JWT or Auth session. Captured owners/ACLs are not asserted equivalent. Nested tax/other dependencies outside the nine direct helpers, full source/side-effect backup, restore and production approval remain separate.

Only the reusable verifier and this review belong in the repository. The private checkpoint and real salary recovery data must remain outside Git/Issue comments. These results narrow the helper gap; they do not certify a complete production dependency closure or salary repair.
