# Common allowance application status

Source inspected: main `c3042d23e01a176e28b9ac51dfb91d814008e057`.

The individual settings page already embeds `PayrollUnitConditionsPage`. That
reader connects effective company items into the selected earning/deduction and
hour/day/month section. The shared calculator reaches the same common resolver
from attendance refresh, attendance-detail synchronization, individual-setting
refresh and monthly generation; no second calculation path is added here.

Read-only aggregate observation on 2026-10-24: zero company activations, zero
payroll-type activations, zero publications, one saved company state and zero
additional active items. Two company rate-setting records have positive named
legacy allowances. This observation does not identify the user's company or
approve any financial application. No identities, names or amount values were
read for this aggregate check, and no production writes were performed.

With no activation the deployed resolver deliberately returns no effective
items. The old UI consequently hid the company card, and its empty-month
Offstage condition could hide the panel entirely. This patch exposes the known
unregistered/future activation state using the existing reader's `source` only.
Older/missing/unknown sources are not mislabelled unregistered. Finalized,
blocked, history-missing and already effective item displays remain unchanged.
The status does not claim that editable company rates have been applied.

The existing company common settings screen already offers `対象を確認して反映`.
The legitimate administrator must review its actual preview and explicitly
approve the selected payroll type and start month. Unknown results retain the
same command for read-only receipt lookup. No postgres activation, forged JWT,
made-up amount, old-install replay or bypass of the preview is appropriate.

This patch changes no calculation, settings, payroll amount, ACL, SQL function or
activation record. Four related tests cover classification, older/unknown
sources, preserved special states and the empty monthly embedded panel. Local
Flutter execution was not performed; CI execution is required. Existing
synthetic SQL-to-PDF evidence is reused and is not actual-user amount proof.

New Japanese display/help strings use the existing language-controller fallback.
The root integration owner should add translations together with shared English
changes; this task does not edit the shared translation map.
