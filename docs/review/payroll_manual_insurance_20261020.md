# Explicit individual insurance monthly amounts (review only)

This is a supplemental opt-in contract, not a recovery of missing historical automatic premiums. No production change or automatic profile migration is included. Based on PR1297 head 48c67c4a631f6c4a96ac2023270aa0b8f81e0754, including saved named-insurance fallback.

Only a prepared server advertises manual_insurance_contract_version=1 in its existing authenticated condition reader. The existing insurance selector then offers individual monthly employee amounts. All five named amounts require explicit integers, including zero for not applicable. Blank is rejected. No enrollment flag, birthdate or standard remuneration is fabricated or stored. Without the server contract the new option is absent; existing manual profiles are read only.

The effective-month saver, optimistic version check, confirmation, audit, access checks, refresh and finalized-statement guards are reused. Rates and legacy fixed modes retain their existing validation/calculation. Manual employee premiums join the existing social deduction before the existing income-tax calculation. Income override and resident-tax resolution are preserved. Insurance amounts are merged into named statement fields, never split from an aggregate. Fixed-frame edits preserve every other manual amount and existing income override. Rates users are not switched to manual.

The SQL remains outside migrations and fails closed unless all four original private function-body hashes match. It retains function OIDs, owners, ACLs and security modes. Installation alone changes neither conditions nor financial rows. Its activation requires separate reviewed deployment and backup/restore readiness; this PR does not deploy it.

Synthetic PGlite integration passed: unchanged rates/legacy, missing/null/blank/fraction/negative/overflow rejection, explicit zeros, no invented flags/base, CAS and authorization, unchanged prior month, same retry, existing income calculation, named totals/net, duplicate-insurance blocking, common allowance publication plus unrelated individual edit, and finalized statement preservation. PostgreSQL 17 and Flutter checks are defined in CI and remain pending until run. Real production settings, amounts, HTTP/JWT and device use remain unverified. The historical automatic-link report remains unresolved.

The common saver/bridge/effective candidates used by the fixture are existing dependencies copied without modification, not new implementations. Do not apply the common chain or this candidate automatically from a test command.
