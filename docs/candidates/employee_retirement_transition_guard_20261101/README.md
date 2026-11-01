# Worker transition guard — isolated review only

`deployable:false`. This is not an installer or a reinstatement feature. No production SQL or data is changed. Existing #1710 and #1713 source remains untouched.

The new AFTER UPDATE row trigger rejects non-active → active transitions, including NULL/unknown old status, by raising an exception. It never silently returns an unchanged row: the legacy invitation function writes membership before updating the worker, and an exception must roll that preceding write back. There is no GUC, owner, service-role, nested-trigger, or definer bypass. New active INSERT and active profile updates remain possible; this is not a complete duplicate-identity or privileged-owner defense.

Native tests use the exact captured old ensure function and the exact legacy approval function extracted from the fixed migration. Schema, Auth, recipient metadata and notification sink are synthetic fixtures, not hosted GoTrue, RLS or deployed Edge proof. The existing #1713 repair is invoked in the fixture without modifying it. Tests distinguish guard rejection of old ensure from successful UUID/history access after that repair.

The race is an old ensure call blocked on an already locked worker row **after the guard exists**. It does not prove installing the guard drains old frames, nor prove production admission closure. Current trigger/partition/ACL/catalog inventory, active→inactive effective-date and reason history, authorized reinstatement, real identity and safe cutover remain unresolved. Existing inactive also historically meant preregistration; do not backfill fictitious retirement events.

Do not ship guard alone: old ensure would attempt active and fail, including on a history-read path. Production approval, exact baseline, #1713 dependency, existing-frame barrier and forward repair must be reviewed together. Never delete originals or remove a used guard to restore implicit reactivation.

Run only the dedicated isolated PostgreSQL 17.6 workflow. The runner refuses non-loopback hosts, unexpected database/user, production URL/secret variables and server-address mismatch.
