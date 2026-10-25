# GPS clock-in and scheduled checkout confirmation — candidate

User-confirmed contract: GPS setting selects weekdays, clock-in time, checkout
confirmation time and a site/route. Existing GPS clock-in ±5 minute / proximity
logic is unchanged. The checkout time is a reminder, never a clock-out write.
Only the real saved personal clock-out transitions into the existing required
reporter-signature flow. Another roster member's shared report can satisfy report
registration, but does not clock this member out. Shared-report receipt and
supervisor collection belong to the existing report authority contract.

## Source / authority

The new public save delegates to the existing GPS save and checks its exact
worker/destination result in the same transaction; ambiguous old multi-company
selection rolls back. A revision CAS protects concurrent setting edits. Midnight
crossing is explicit: checkout before clock-in means next day; equal times are
rejected. Minutes only, Asia/Tokyo only, unique weekdays.

Actual GPS clock-ins are captured to reminder-only source snapshots. Updating
future settings first captures any current open source and never moves its old
reminder deadline. Settings save first locks the same GPS schedule row as
the existing clock-in writer, then captures sources; an uncommitted old clock-in
cannot be skipped while future settings replace its destination. This adds no
payroll-scope lock and changes no existing GPS writer body. Initial setup does not activate old clock-ins from days before the
first configuration. Real clock-out existence resolves the source; notification
payload, navigation return, local clock or shared-report entry cannot resolve it.
Thirty-minute postponement is server persisted with source fingerprint CAS.

Every public RPC uses the independently reviewed live-session helper pinned at
MD5 `9ca270fa06ff48883705cea5d18a8f2f`. PUBLIC/anon/service-role grants are revoked;
only authenticated gets public RPC execute. Tables/internal helpers are private,
RLS enabled with no client table policy/grant. Reminder-only foreign keys
clean up their private child rows on an already-authorized source/target deletion;
this adds no AV deletion right and changes none of its existing guards/audit.
No financial/history table is cascaded and no DROP CASCADE is used. Company feature check only exposes
a scoped management recovery action; it does not bypass ordinary app navigation.
Administrative actual corrections and shared-report/signature override retain
server role/audit checks outside this new reminder unit.

## Native device boundary

`read_my_scheduled_checkout_notification_plan` emits concrete UTC fire instants
from server Tokyo weekdays and overnight logic for the next eight-day window.
Actual source reminders (including postponements) replace same-worker/day generic
configuration placeholders. Native bridge may schedule generic notifications
before clock-in; tapping one always rechecks actual work before prompting.

NativeUserNotifications/MethodChannel implementation belongs to the separate
native owner. Permission is requested from an explicit user action, not polling.
Denied/unavailable means OS notices are unavailable, not delivered. Native tap and
foreground due signals only request a server check. Logout, disable, real clockout
and actor changes cancel or replace this feature's tracked notifications. Closing
the app cannot force it open: iOS local notification delivers if permitted; next
app open/resume rechecks the persisted server state. GPS background clock-in
remains subject to iOS location delivery/force-quit constraints. Other members'
report-created notifications need server notification / push integration and are
not supplied by this local time-based bridge.

## Root integration (shared files intentionally untouched)

1. Replace GPS-only time popup at each GPS selection entry with
   `showGpsWorkScheduleDialog`; save both times through repository.save, using
   revision from loadNotificationPlan.configurations. Non-GPS save stays as-is.
2. Normal authenticated child is `ScheduledCheckoutGate` INSIDE the existing
   outer report gate's ordinary Offstage child. Report gate has priority.
3. checkoutBuilder opens the existing exact personal clock-out target. Its saved
   callback awaits report-gate requestCheck before return, then schedule rereads.
   optional group checkout still precedes personal reporter input in outer flow.
4. Outer report back controller forwards to
   ScheduledCheckoutGateController.instance.handleSystemBack only if no report
   block. The schedule handler swallows root-back and pops only its restricted
   Navigator while confirmation is pending. Programmatic ordinary routes remain
   Offstage. ManagementBuilder is allowed only for server canManageAttendance.
5. Refresh both schedule gate and native plan after GPS clocked_in, setting save,
   disable, personal clock-out and authorized management corrections. Bind native
   taps/due before cold-start consume; acknowledge only after successful same
   actor/session server check. No notification payload is an unlock instruction.
6. Native owner adapts loadNotificationPlan's typed DTO to its own planner; use
   repository.currentSessionIdentity and static sessionIdentityOf(event.session)
   to retain same-UID session-change events. Never log JWT/refresh tokens.

## Verification status

New focused PG17 workflow uses disposable loopback only. It copies the exact
reviewed session helper; JWT surroundings and old GPS-save adapters are synthetic.
It tests OFF/capability, source-bound due, server UTC planning, no auto-clockout,
revision CAS, overnight, postponement/reload, source preservation on setting edit,
clock-out resolution, disable, management feature flag, other-worker/invalid
session/role and private-table refusal. No real GoTrue or Apple runtime proof.

New Flutter tests cover DTO strictness, SDK async A→B→A invalidation, exact source
CAS, one-plan-RPC, restricted Navigator/back/management, failed reads, persisted
postpone and the two-time popup. Local Flutter execution was not attempted.
Node syntax and diff checks only; remote Native/Flutter are required next.

No rollout row, cron, actual notification, app/Auth/financial data mutation or
production installation has been performed. Native owner + final root hooks,
English resource integration, actual iPhone notification permission/background
and report-gate handoff remain mandatory before release.
