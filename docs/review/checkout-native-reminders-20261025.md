# iPhone checkout reminder bridge candidate

This adds local scheduled reminders, not automatic checkout and not a server
authorization capability. No production application or phone verification occurred.

## Owned files and host integration

`prepare_ios.sh` retains every existing generated AppDelegate bridge, registers
one `SkoCheckoutReminders` delegate proxy after Flutter registration, and appends
the tracked Swift fragment to the generated AppDelegate. Reused projects get the
same source. The old notification settings channel remains intact. Notifications
outside this feature are forwarded to the prior delegate; cancellation only
removes this feature's own identifiers.

`CheckoutNativeReminderBridge` exposes `authorizationStatus`, explicit-action
`requestPermission`, `schedule(sourceId,fireAt)`, `cancel(sourceId)`, `cancelAll`,
`consumePendingTap`, `acknowledgePendingTap(sourceId)`, and separate `taps`/`due` streams. No auth/gate/roster or
checkout repository file is changed here. The schedule/gate owner must attach
listeners then drain a cold-start tap, re-read the current actor/source on the
server, and only invoke the existing manual checkout confirmation flow.

Channel `com.skworks.skWorks/checkout-reminders` has native methods `status`,
`requestPermission`, `schedule`, `cancel`, `cancelAll`, `consumePendingTap`,
`acknowledgePendingTap`.
Schedule arguments include sourceId and absolute `fireAtEpochMs`; optional Dart
title/body are generic and native always uses fixed generic lock-screen copy.
Source IDs are opaque actor/source keys (160 ASCII characters maximum, letters,
digits, colon, underscore, dash). Fire time must be future and within eight days.
The rolling weekly coordinator must re-plan on settings/time/account changes.

## Cancellation and notification behavior

The native epoch and per-source revision cancel delayed authorization work.
Each scheduling attempt receives a unique identifier. If an old add callback
arrives after cancellation, cleanup removes that attempt only, never a newer
schedule for the same source. Feature IDs are retained across process termination
for cancellation and cold-start handling. Logout/account switch must await
`cancelAll`; clockout/disable/date replacement must cancel the relevant sources.
Owner state must be checked again after awaited bridge results; permission or
scheduling success is not proof that the same account is still active.

When due in foreground, the native delegate emits `notificationDue` and permits
the iOS banner/list/sound. Tapping emits only sourceId; if Dart is not listening,
the source is retained for `consumePendingTap` (peek). It is cleared only by
explicit acknowledgment after a fresh same-session server validation, or by
logout/retirement cancellation. Ordinary replanning calls
`cancelAll(preservePendingTap:true)`. There is no direct navigation,
unlock, receipt write, clockout, wage write, automatic signature or identity
change. Member-reported notifications from another phone require the server
notification/push contract; this local bridge does not implement APNs.

Permission denied, provisional, ephemeral, unsupported and unavailable are distinct
states. A successfully registered local request can be delivered by iOS without
launching Dart, but delivery/visibility depends on system authorization, Focus,
notification settings and device state. It cannot force-open a closed application.
Real device checks remain necessary for permission denial/allow, foreground,
background/cold-start, Focus, timezone change, postponement, logout cancellation
and changing accounts while the permission prompt is open.

## Validation

The Python check inspects exact generated-source integration and the platform
contract. Dedicated remote CI typechecks the real iOS UserNotifications APIs,
and 17 Flutter channel tests cover status, arguments, cold-start acknowledgment,
due/tap separation, invalid payloads, cancellation and late responses. Native
runtime scheduling/races are not claimed as device-tested by source/type checks.
Existing complete iOS CI must also compile the generated application.

References: Apple Developer, “Scheduling a notification locally from your app”
and `UNUserNotificationCenterDelegate` (consulted 2026-10-25).


## Device coordinator host contract

`CheckoutNativeReminderCoordinator` is independent of the repository package.
Its constructor takes loadPlan, currentActorId, currentSessionIdentity,
sessionChanges, requestGateCheck(sourceId), and an optional native bridge.
The only lifecycle methods are `init()`, `refresh()`, `dispose()`; status and
actual authorization are exposed as ValueListenables. An authenticated shell
owns one coordinator. Dispose the old one when replacing the actor shell.

Adapt the strict scheduled repository plan into `NativeCheckoutDevicePlan`:
actorId, sessionIdentity (capture before load and reject if changed afterward),
serverTime, notifications mapped to sourceId/fireAt, and hasDueConfirmation.
Those instants are already computed on the server from its timezone/weekdays
and source-bound postponement; the device never invents future dates or hours.
Use `ScheduledCheckoutRepository.sessionIdentityOf(event.session)` for the
sessionChanges stream, preserving every event's UID/SID. Reading the SDK's
current value for each emitted event would lose an A→B→A transition.

`requestGateCheck` returns true only after a fresh actor/session-scoped server
read verified the cue or identified it as stale. It may signal the existing
scheduled/report gate afterward, but a local signal alone is not validation.
An empty source means an authorized full-scope due check; it never chooses an
arbitrary report. Tap source strings never become navigation or unlock proof.
Network failure or actor changes keep a pending cold-start cue unacknowledged.
Replanning retains it and retries after a later successful read.

Refresh after server-confirmed settings save, disable, postponement, actual
checkout, source changes and app resume. Postponement must succeed on the server
before refresh, rather than adding 30 minutes on the device. Permission is never
requested automatically; explicit user enable UI invokes the bridge permission
action and then refreshes after rechecking the same actor/session.

A slow old server load does not own the native queue or block cancellation.
Native work is serialized, old responses are invalidated by a generation and
emitted-session latch, and logout immediately cancels this feature's reminders.
At most 32 unique, future, UTC server instants within eight days are accepted.
Unsupported/malformed/permission/partial-schedule states are distinct; failure
never becomes completed checkout or registered report. Eighteen coordinator
regressions cover same-UID/session ABA, account replacement, logout, server
failure, cold-start acknowledgment and preservation, disabled plans, denied
permission, exact instants and partial scheduling failure.
