# Authoritative reporter-registration gate — stage 2 candidate

Depends on stage 1 saved-checkout continuation and the separately reviewed backend `read_pending_checkout_report_registration()` contract. This is a candidate, not a production-enabled completion claim. No local Flutter was run and no production data was changed.

## Boundaries

`app_v2.dart` wraps the entire normal Navigator/help/scroll-chrome stack in `CheckoutReportGate`; merely wrapping the authenticated home would leave already pushed pages accessible. `auth_gate.dart` activates the gate only after its existing authentication/onboarding checks. The existing identity-disposing `AuthenticatedNavigationBoundary` is unchanged. Replacing the home route does not deactivate a pending gate. A different authenticated actor resets the dedicated report Navigator; stale responses cannot unlock another actor.

The normal Navigator stays offstage with input blocked, preserving its state and unsaved drafts. The gate uses its own Navigator for the source-pinned report and required signature capture. A back observer mounted before MaterialApp redirects system back into the dedicated Navigator; root back is blocked; a nested signature screen can return to the report. Notifications/deep links pushed to the normal Navigator remain hidden until server registration clears. Returning from background rechecks the server. Startup pending/unknown never means an empty backlog.

The immediate personal checkout page asks the global gate to check synchronously, then returns underneath it. This avoids opening two competing report editors. For a site checkout without a route, the dedicated restricted Navigator first offers the existing optional group-checkout flow, then opens the report. This preserves the previous order (personal checkout → optional member checkout → reporter registration) without exposing the ordinary Navigator. Rechecks of the same pending source do not open that step twice; restart reloads candidates using the saved personal anchor and the existing idempotent group API. The stage 1 fallback remains for tests/environments without an active authenticated global gate. Proxy clock-out does not automatically create a new legal reporter obligation.

### Checkout entry audit

- Manual, location/photo and saved/unknown-result recovery all converge on `AttendanceVerificationPage._finishSavedVerification`, including route checkout. Its personal-save gate request remains authoritative; route visit arrival/departure only edits visit evidence and routes final checkout back through that page.
- `GpsAutoAttendanceService` is automatic **clock-in only**: the latest `attempt_gps_auto_attendance` source inserts the literal `clock_in`, and returns `already_recorded` for an existing clock-in/out. It is not a missing personal clock-out trigger and no GPS behavior is changed.
- `GroupCheckoutRepository.commit` invokes `commit_group_checkout` for selected peers. The optional UI now stays inside the restricted Navigator before reporter registration. It does not assign an obligation to the proxy actor in place of those peers.
- The administrator `force_manage_attendance` writer can create a saved clock-in/out pair during direct correction. After successful mutation, its repository now requests a server recheck only when the response still belongs to the same authenticated/activated actor. It does not locally infer that the administrator is the affected worker. A failed write never triggers a check. Bulk/past-attendance requests, formal cloud entries and report-approval projection are separate approval/formal-record operations, not the personal checkout UI.

## Unlock contract

The only release signal is a fresh actor-scoped server RPC response with `{schema:1, actor_id, enforcement_enabled, effective_from, items}`. Missing fields, unknown states, mismatching actor, invalid identity/date/destination, duplicate sources and read failure never become an empty list. Blocking states are `report_missing`, `source_conflict`, `report_input_incomplete`, `reporter_signature_missing`; nonblocking states are `reporter_saved_waiting_supervisor`, `signed_projection_unverified`, `completed`. No state is shown as actual payroll success by this client gate. `source_conflict` does not open an editor.

`DailyReportPage` restricted mode pins actor, destination, company for an existing report, worker and source clock. It forbids fallback to another destination, date/destination changes, saved-list/notification/evidence/print navigation, responsibility signing and root back. Normal report fields and reporter signature retain their existing save RPCs. Save/sign callbacks only request another server read; neither callback nor local signature evidence releases the gate. Same-source server refresh preserves the editor/draft; moving to the next source creates a new scoped Navigator.

The responsibility signature is intentionally not required to use other app screens after authoritative reporter registration. Its later signature and payroll verification reminders are owned by the backend/notification stage. A responsibility-waiting or projection-unverified state is not called payroll completion.

## Rollout blockers

The backend candidate is initially OFF and still lacks proof for all vehicle-meter/source-attachment mandatory conditions. An empty response while OFF is not proof that mandatory enforcement is enabled. The client validates the explicit capability/start-date envelope and exposes their actual values. OFF must have a null start date and no items; absence is unknown. Root must coordinate the rollout decision and verify backend required-field coverage before enabling this client in production. Daily reminders, authoritative payroll-success closure and final old-day recovery require their own server integration evidence. This UI cannot substitute for them.

A failed read keeps the editor's saved/unsaved state mounted behind a retry screen. Server drafts survive restart; unsaved field text is preserved in memory while this process remains alive, not yet a durable offline draft across OS termination. This limitation must not be presented as offline persistence. A user-controlled login recovery button invokes the existing sign-out/re-authentication path; the gate never silently logs out the current session. Normal authentication and onboarding are not replaced by a fake report-completed flag.

## Verification prepared

Synthetic parser tests reject malformed/foreign/unknown unlock responses. Widget tests cover normal-screen isolation, local-callback non-unlock, pending/failed reads, retry, back, next-source replacement and actor-response races. These are client fixtures and do not prove actual RLS, sign RPCs, required-field validation or daily notification delivery. The dedicated remote Flutter 3.47.5 workflow runs targeted analysis and related tests; no passing result is claimed yet.
