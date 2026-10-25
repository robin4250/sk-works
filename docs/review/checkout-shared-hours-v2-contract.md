# Shared work report and individual-hours annex v2 — review only

This candidate is separate from the tested v1 candidate. It has not been run in
Native PostgreSQL, integrated into the application, or applied to production.
It must not be enabled or described as ready based on v1 tests.

The rollout only enrolls a new report through the owner-only
`checkout_shared_hours_private.begin_work_report(report_id)` before its first
signature. An immutable protocol row selects v2. Existing v1 signed reports and
ledger entries are never converted, even when the rollout starts on their day.
Turning enrollment OFF never reinterprets an already enrolled v2 report as v1.

The reporter signs frozen work facts and roster. That basis explicitly excludes
the private hours annex. A member may subsequently confirm only their own real,
closed-shift hours. The confirmation records actor, time, exact source fingerprint,
revision and the immutable work-basis hash without clearing the work signature.
An authorized manager has a separate reason-required API; manual clock evidence
is accepted by the existing canonical reader, without fabricated GPS evidence.
Missing or conflicting clock evidence remains unavailable. Managerial handling
of missing route evidence requires a separately audited source contract; this
candidate does not loosen ordinary route requirements.

Before the first work signature, source-bound group editing follows the shared
report helper. After it, ordinary members cannot edit another member's hours.
Frozen work/roster changes still require the existing approved-correction flow.

The final supervisor signs the displayed combined scope. The shared report API
must compare its server-issued combined signature fingerprint, then invoke
`prepare_supervisor(report_id, annex_fingerprint)` under all roster worker/month
locks. A private transaction/actor/report-bound context is required by the v2
capture path. Direct use of the old supervisor endpoint cannot finalize a v2
required annex. Unconfirmed hours, source changes, stale revisions and a changed
work receipt prevent finalization. No unknown quantity becomes zero.

The separate v2 ledger binds the first work-signature event, each individual
confirmation, final supervisor signature, exact source scope and annex fingerprint.
It explicitly does not claim the first reporter approved later, unknown hours.
The quantity evidence retains contract versions; v1 evidence remains unchanged.

Required remaining proof: current shared helper source pins, Native two-member
first-reporter/peer-still-working sequence, late own confirmation preserving the
first signature, another member's supervisor collection, stale-dialog and direct
endpoint refusals, manager audit, old/new source invalidation, v1 history equality,
real GoTrue/PostgREST, DTO/card integration and rendered PDF evidence.

Approved corrections retain the original worker confirmation as immutable
history. After the exact approved editor obtains a new reporter signature, the
optional correction adapter may copy a previous **clocked** attestation to the
new work epoch only when the original finalized ledger, old signed roster,
current normalized worker facts, date/destination and raw clock-source hash all
agree. The new confirmation kind is `approved_editor`; the private copy receipt
records the request, exact editor session, original actor and both confirmation
and work-event IDs. It never labels the editor as the worker or as a manager.
Changed facts or sources are not copied. Manual management sources require the
existing authorized manager to confirm again. A client has no direct execute
permission on the copy routine. The additional Native wrapper exercises the
original approved-draft and signature writers with this actual hours module;
its approval/Auth surroundings are synthetic, not a real GoTrue proof.
