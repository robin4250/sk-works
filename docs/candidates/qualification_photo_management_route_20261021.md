# Qualification saved-photo management route candidate

Base: PR1313 head `9b364ff28f7b5cb188043a51463467aebbc50ca7`.
Isolated branch, no production backend or main update.

Existing QualificationCertificatePage holder/qualification selection opens a new
management route. The original view-only images and registration record remain.
The loaded dataset now includes its existing company_id; the entry pins that
company, current actor and selected qualification id in a ValueNotifier. Parent
reload/revocation/disposal invalidates it rather than guessing another membership.

The product switch SKO_ADMIN_SAVED_PHOTO_MANAGEMENT is compile-time default false.
No rollout changes it. OFF route shows unavailable and help without RPC/path/open.
Even explicitly enabled requires current session, foreground, selected scope and
photo reader; missing dedicated server readiness closes the runtime before paths.
All qualification backend guards remain HOLD.

The route owns app lifecycle, selected context and Auth streams; token changes,
signedOut, actor/company/target changes, background and stream failures revoke
the runtime and selection UI. Old late results are rejected. Reopening is required.
Existing fixed-token runtime/factory/native/submission components remain responsible
for sending and durable request identity.

For a new request, fresh dedicated authorization precedes a fixed-company/target
saved-photo read under explicit captured Authorization. Existing draft page lets
the user choose saved photos/order. The baseline is fetched again after selection,
and the existing Prepare contract checks it before a locally generated UUID is
persisted by the submission repository. Existing photo signer only displays saved
images; no upload or Storage object delete is introduced.

Pending identity is read/recovered first. The page never creates another request
while one is pending. Submit and cancel require explicit confirmation and call
the existing repository. Status and cancellation/rejection reason are displayed;
uncertainty offers same-request recovery. Explicit acknowledged non-draft receipt
can close local pending, without changing the server record. No self approval,
direct qualification DELETE or legacy attachment-update fallback exists.

The ? help contains initially collapsed operational details. This candidate has
not been enabled in production, installed or exercised on iPhone. New OFF/missing
session widget fixtures and existing runtime/SDK/submission regression checks
must pass dedicated CI; successful ON UI end-to-end and real native durability
remain separate requirements. No legacy repository mutation APIs are invoked.
