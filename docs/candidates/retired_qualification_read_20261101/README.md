# Retired qualification read — isolated source review

`deployable:false`. Product repositories, authentication code, production SQL and financial data are unchanged.

The dedicated PostgreSQL 17.6 job calls the existing Dart `QualificationCloudRepository.currentWorker/loadAll` and `QualificationCertificateRepository.loadAll` through the real Supabase SDK. A small loopback HTTP adapter translates only allowlisted SDK reads and two RPCs into isolated PostgreSQL statements. **It is not actual PostgREST or GoTrue.**

The fixture first runs the exact captured old `ensure_current_user_worker` and records the existing reactivation counterexample. It then resets only the synthetic worker status, applies the exact #1713 review repair, and repeats the actual repository reads. It verifies the existing UUID, inactive state, stored qualification fields and attachment paths; a database fingerprint also covers the unchanged foreign-person/company qualification rows. No attachment bytes or Storage objects are fetched or created.

No permission helper returns unconditional allow/deny: pinned existing `current_feature_permissions` and `private.has_company_feature` bodies run against a minimal synthetic membership/permission schema. Selected existing worker/master/qualification read policies are used unchanged. These are **selected source policy composition**, not the current deployed policy set, table constraints, real live SID/account checks or production authorization proof. The synthetic `auth.uid/JWT` fixtures and ACL setup are explicitly not production Auth.

The test does not solve multi-company `limit(1)`, session changes during these legacy reads, safe replacement/drain of already running old functions, qualification editing, reinstatement, payroll or actual iPhone use. #1713 remains undeployed. Successful source/fixture reads must not be reported as production availability.

Inputs are fixed in `dependencies.json`. The old source and repair are obtained by a second checkout of a fixed commit under `build/`, then hashed before use. Product repository bytes are hashed too. The database must be named `retirement_fixture`, use the inspected disposable service address through loopback port 55442, and reject production URL/secret variables. The HTTP adapter binds only 127.0.0.1:55443. No production endpoint is queried.
