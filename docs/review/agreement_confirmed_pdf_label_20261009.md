# Mutual agreement PDF label

Depends on #816 exact `a688be0f2bb200449ffdc4928b9c614a9b75a54c`.
The immutable agreement adapter has always set the generic record status to
`draft`, although its server requires both companies to confirm the latest terms.
The generic footer therefore misleadingly printed “下書き”.

An explicit adapter-origin flag now selects “双方確認済み・第n版”. The status remains
`draft`; no company approval, monthly certificate finalization, database value,
permission, RLS, migration or invoice/payroll layout changes. A separate formal
agreement finalization workflow is not invented. Monthly preview/draft/finalized
labels remain exactly as before. Old v1/v2 and new v3 saved agreement documents
use the same origin-specific label; their financial snapshots remain unchanged.

CI creates actual PDFs from the disposable server fixture's v1/v2/v3 snapshots
and checks text/PNG against the three monthly states. Local Flutter is unavailable.
This is a display correction, not a claim of production rollout or full workflow
completion.
