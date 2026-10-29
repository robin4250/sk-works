# Invoice recovery: existing panel and Auth history (OFF)

Base main: a891fbf95636038ef7252ea7b1de8ee67545bfce.
The existing InvoiceNoticeApprovalPanel now accepts the existing recovery
controller directly. After one ambiguous confirmation it performs the scoped
immutable result read. Missing/error results expose only a read-only result
check; they never reopen a ticket, resend approval or call the legacy saved
approval callback. The existing entry widget forwards this optional binding.

Recovery can observe a supplied SupabaseClient directly. It captures current
actor/SID before subscribing, validates identity in initial/refresh events,
and terminally invalidates on signedOut, signedIn (including same-identity ABA),
identity mismatch, stream error or stream completion. The SDK initial replay is accepted only for the first event with the exact
captured Session object; a later same-SID signedIn remains terminal. Same-SID token refresh
retains the pending operation. Token parsing is UI invalidation only, never
authorization; the private reader continues to enforce live session/company
conditions. Cancellation is memory-only and does not claim server revocation.
The observer lives on the invoice controller, without shared Auth file edits.

The existing panel removes stale receipts and result-check actions on this
invalidation. Background, target/revision replacement and disposal invalidate
the whole recovery controller, not only its ticket. Generation checks reject
late command/readback replies. Auth subscriptions cancel at invalidation/dispose.
Eight additional tests use the real Supabase SDK with synthetic auth HTTP
responses to cover initial replay versus immediate same-SID login, logout/login ABA, same-SID refresh, different SID, existing
panel success/read-only retry, pending read logout and background.

Release remains fixed false. The production factory is still disconnected from
the private confirmation/result transport and this optional recovery binding.
No public RPC, grants, database schema, original documents, signatures, shared
Auth/navigation code, deployment, delivery or real-device verification changes.
Authenticated public transport/real live GoTrue proof, route construction with
validated operation preview/hash, and production gates remain separate work.
