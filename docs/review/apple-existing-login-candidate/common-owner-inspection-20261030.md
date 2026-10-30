# Common Auth owner for isolated successor inspection

The existing application `AppAuthMutationGateway` now owns a credential-free
inspection lease for the captured SDK session. The existing isolated Apple
successor preparer acquires it before any Auth/company inspection or delivery,
and holds it until invalidation/disposal. Password, OTP and profile mutations
already using that gateway cannot overlap this inspection. Existing external
Google/Apple flow admission is closed while it is held.

Logout retires the read-only inspection synchronously, before awaiting SDK work;
it does not wait for a stalled inspection response. The preparer cancels its
owned HTTPS delivery and rejects late results. The gateway's existing logout
quarantine and persistence behavior remain unchanged. A later inspection cannot
be released by an older lease. Live SDK Auth events or stream failure retire the
lease, and its scalar check also refuses a silently replaced SDK Session object,
including byte-equivalent same-UID recovery. The initial cached SDK replay alone
is not treated as a new operation.

This reuses the existing gateway and preparation components; it does not add a
second global client owner or perform global setSession. SDK callbacks, automatic
refresh and raw SDK calls are observed, not controlled. Silent unobserved A-B-A
writes cannot be proven absent. Global compare-and-swap/persistence/adoption,
hosted enrollment and ACK endpoints, restart recovery and iPhone verification
remain incomplete. The separately owned in-memory Apple coordinator remains an
OFF candidate, and all existing login routes/settings stay unchanged.

Focused pinned-SDK cases cover repository write exclusion, external admission,
lease replacement, immediate logout, SDK A-B-A, silent same-UID restore and the
actual isolated-preparation composition. CI results are recorded separately;
no local Flutter execution or production activation is claimed here.
