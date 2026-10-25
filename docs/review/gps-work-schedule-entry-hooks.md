# GPS schedule selection entry hooks

Exact existing baseline: main f1c7658a375e5d857fa49da21a5df21833b8f3e6.
Only AttendanceSelectionPage, AttendanceWorkplaceSelectionPage,
WorkDestinationSelectionPage and GpsAutoAttendanceService are owned here.
DailyReportPage, AttendanceVerificationPage and existing report gate remain owned
by the final UI integrator.

The main attendance selection shows one dialog with both clock-in and checkout
confirmation times. Loading and editing preserve the actual registered times,
weekdays and revision. Saving GPS uses the new atomic schedule RPC. Existing
manual/photo paths and selected vehicle are retained. Changing only destination
on either alternative page preserves configured times; legacy GPS with no saved
checkout time opens the dialog once before save. Ambiguous multi-worker/company
configuration fails instead of silently using its first row.

GPS successful status `clocked_in` alone refreshes the schedule gate and native
plan. No other position result, interval, proximity, work category or auto-clockout
behavior is changed. Native permission is requested only on the user's GPS save;
rejected/unavailable permission means foreground-only confirmation and is shown
truthfully. Runtime refresh uses the authenticated host's existing singleton
native coordinator and never substitutes a notification for saved server state.

Dependencies: scheduled checkout core PR1392 (including maybeCreate / draft.label),
native bridge/coordinator PR1391. Apply these hooks only in the final combined
integration tree. Root should analyze all four existing files + new flow helper
and run six selection flow tests, the three core GPS tests and existing GPS
selection/restoration regressions. Local execution was limited to diff/source
inspection; Flutter must run remotely.
