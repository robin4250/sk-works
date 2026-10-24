# Authoritative checkout registration and daily reminder candidate

Review-only baseline: main `1f05f3b2cb766dc7b978145f8ebd98a6002f92ea`.
No production application, activation, cron registration, actual notifications or
financial writes occurred. Proxy responsibility is explicitly outside this unit.

Install candidate order: registration, validators, reminders, schedule. Rollout
contains no rows and defaults OFF. Root must review activation/start-date scope
and installed prerequisite definitions before any production installation.

## Gate API

`public.read_pending_checkout_report_registration()` has no parameters:
`{schema:1, actor_id, enforcement_enabled, effective_from, items}`.
Enabled applies only to an active company rollout. For multiple memberships,
effective_from is the earliest enabled start; each item is filtered against its
own company's start date. OFF returns false/null/empty. No legacy backlog is
silently activated. Actor scope is current membership and worker.user_id, never
an arbitrary company/worker passed by the caller, nor created_by as a proxy guess.
Account access is checked at the public boundary. Internal reader is revoked.

Items contain company_id, worker_id, work_date, exactly one destination
(site_id/route_assignment_id), report_id, source_clock_in_id, clock_out_id,
registration_state, blocking and scope_fingerprint. The fingerprint is an
invalidation token, not an authorization capability.

| State | Blocking |
|---|---|
| report_missing | true |
| source_conflict | true |
| report_input_incomplete | true |
| reporter_signature_missing | true |
| reporter_saved_waiting_supervisor | false |
| signed_projection_unverified | false |

Completed items are omitted. A saved reporter signature unlocks while report
status is still draft. The supervisor signature is not an unlock prerequisite.
Missing/ambiguous evidence remains blocking and needs a recoverable admin route.
The reader never signs, repairs attendance, calculates money or changes payroll.

## Required saved input

Persisted description, roster, nonnegative non-null overtime/early/night values,
valid work category and vehicle odometer are checked. For managed vehicle claims,
the existing committed meter invariants are reproduced from
`20261008162618_attach_vehicle_meter_to_report.sql`: ended exact-scope claim,
immutable event, report link and all saved meter snapshot fields must agree.
The existing guard is exact-pinned at installation (body MD5, postgres owner,
SECDEF, return type, volatility, empty search path and owner-only execute ACL).
No optional legacy vehicle selection is guessed to be a managed claim. Existing
save/sign/vehicle writer functions and triggers remain untouched.

## Notification and projection contract

`deliver_daily(after_actor,limit)` is private owner-only and processes at most
500 actor accounts per call. It returns next_actor, has_more, failures and actual
sent/deduplicated counts. Membership and active worker filtering are reapplied.
Receipt key is company/worker/source/recipient/JST-day/reason, independent of
app_notifications.read_at. Receipt and enqueue are atomic per actor. Before enqueue, all report roster
worker/month scopes are locked with the existing exact-pinned canonical scope
helper, then report/roster/source rows are share-locked and the state re-read.
The routine has a 100ms lock timeout; contention is an explicit retryable actor
failure, and the scheduler retains that cursor rather than falsely succeeding. Failures
roll back that actor's receipts and notifications and remain visible.

After reporter save, the missing-supervisor reason uses exactly:
「現場責任者サイン未完了のためこの日は給与未反映」.
When the supervisor has signed but projection cannot be verified, the reason and
message change; the system no longer says the supervisor signature is missing.
Completed attendance/payroll projection stops further deliveries, without
rewriting old notifications or making read_at a completion signal.

Projection verification requires a signed report with its exact dual-signature
version3 envelope, an unblocked normal calculation, the exact positive formal
attendance row with matching saved hours/category, and an automatic draft
statement updated after signing with standard month attendance/hours detail
matching authoritative attendance totals. Manual/finalized statements are never
rewritten or falsely certified as newly refreshed. This verifies normal detail
projection, not the correctness of every tax, price or insurance amount.

`run_daily_step()` is an owner-only scheduler target with a JST daily cursor and
500-actor batches. Completed cycles restart on the same day so later-created
reports can receive their first daily reminder. A failed batch stays retryable; successful deliveries are
deduped. Root may separately review a five-minute cron registration. This source
registers no cron job. Persistent failures remain operational work, not success.

Notification action_key is `checkout_report_registration`, action_id=report_id.
`public.read_checkout_report_registration_notification(p_report_id)` requires an
actual notification addressed to the actor, current membership, own worker and
checkout source, and active rollout. It returns schema/actor_id/report_id,
enforcement_enabled/effective_from/resolved/items. Other actors or arbitrary
report IDs are rejected; notification read state is irrelevant. Dedicated UI
routing is owned by auth_review_resume, not this backend unit.

## Evidence and remaining deployment boundary

`tool/verify_checkout_registration.mjs` contains synthetic PG17 regression cases:
OFF/actor isolation, source conflict, persisted required input, managed vehicle
missing-event rejection, reporter-only unlock, day dedup/read non-resolution,
next-day eligibility, post-sign reason change, exact source/detail completion,
protected statements, private endpoint grants and scheduler completion.
The next-day fixture moves only synthetic delivery receipt dates; it does not
change the server clock or accept a caller-selected notification date.

Dedicated workflow `.github/workflows/checkout-report-authoritative.yml` uses
PostgreSQL17 loopback and existing locked pg8.16.3 dependencies. It does not use
live Supabase credentials. Node syntax, YAML parse and delimiter checks passed;
Native execution remains pending remote CI. This is not real GoTrue/JWT proof.
The first fixture uses synthetic authorization and manually prepared report/
projection rows. A second Native matrix runs
`verify_checkout_registration_source_chain.mjs`: it extends only a temporary copy
of the existing immutable report/signature/payroll fixture, installs the actual
vehicle attachment migration, and calls original draft save, reporter signature,
vehicle attachment and supervisor signature APIs. It asserts the existing guard
rejects a missing event, then a committed event attachment allows reporter-only
unlock, daily reminder delivery, and normal formal/payroll projection completion.
The fixture replaces only its explicitly synthetic lock helper with the
existing actual scope-lock source, whose owner/ACL/config/body are pinned.
A second connection holds an uncommitted real supervisor-signature write while
the notification runner must return retryable 55P03 and enqueue nothing. A
transaction-only negative control removes just the new lock block, demonstrates
stale enqueue, and rolls back both the unsafe definition and notification; its
hardened source hash is then checked. After the real writer commits, retry must
observe completed projection and enqueue nothing.
Source writer definitions are not edited; all existing producer-body hashes are
checked again by the original suite. Both Native results remain pending remote CI. No local Flutter or
replacement dependency installation was performed.

Remaining product proof: remote Native results, current live catalog prerequisite
pins, source-bound real save/sign chain, bounded rollout preview/recovery UI,
notification UI route and deployed cron observation, then iPhone verification.
Proxy-only checkout responsibility must be specified separately. A group with
the actor as a real worker is still evaluated for that actor's own source.


### Deployed vehicle contract compatibility (2026-10-25)

The current production legacy vehicle writer is pinned at source MD5
`f78e35bf948cc4702f9d65d28d0ac0e6` (postgres owner, SECURITY DEFINER,
void five-argument API, empty search path). Its existing ACL is only observed;
no new routine inherits its legacy PUBLIC default. When the company has no
committed-meter rollout or rollout is OFF, required saved vehicle/odometer
validation uses that existing writer contract, including same-company active
vehicle and non-null clock-source vehicle agreement. No newer vehicle migration
is installed merely to support this report gate.

When company committed-meter rollout is ON, the exact stronger guard and all
claim/event/link relations are mandatory; absent/partial/unknown shapes hold the
gate. Dynamic SQL prevents optional absent relations from preventing deployment
on the observed legacy installation. Missing/changed legacy writer also holds.
Native source-chain proof now first calls the exact observed legacy vehicle
writer plus original report signature APIs with no committed-meter framework,
then installs the newer framework only in the disposable fixture to exercise
strong ON attachment and existing concurrency proof. Diagnostic failure output
contains synthetic fixture rows only; it must never be used against production.
