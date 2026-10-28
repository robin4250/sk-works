# Profile birthday → insurance conditions (build 25 candidate)

Not deployed or enabled. The existing production profile contract has no birthday for the worker (family birthdays are separate). The profile UI therefore disables registration until the new contract is installed; it does not falsely save an unsupported field.

The review-only SQL adds `birth_date` to the existing personnel record and extends its existing payload/application functions. The existing personnel save and approval path remains in use, including approval before changes by employees. Older clients that omit the field preserve it. No DOB is inferred from family records or insurance conditions.

The payroll reader reuses the existing payroll read authorization and checks company/worker scope. New tax conditions display the approved profile DOB automatically; existing effective-dated DOB values remain unchanged, with an explicit choice when they differ. Saving the profile never edits existing tax conditions or finalized payroll documents. Clients on older DBs retain the existing insurance DOB field.

Validation: isolated synthetic PGlite check covers storage, old-client omission, invalid/future date rollback, unauthorized access and company/worker binding. This uses a stub payroll authorization, so it is not real GoTrue/RLS proof. Flutter/Dart validation must run in CI. iPhone verification, current production catalog/ACL review, protected backup and restore procedure, actual authorization/approval integration, and DB deployment remain incomplete. Do not run the staged SQL on production based on this candidate alone. The baseline guard is only source-body matching and is insufficient as a production authorization/catalog guard.
