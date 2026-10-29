# Owned SDK adoption coordinator — OFF bounded adapter

The existing isolated preparation is now composed with an actual Supabase SDK
session write and the existing possession-ACK protocol. This candidate creates
and owns a **new memory-only SDK client**. It does not accept, return, replace or
wrap the application's existing global client. There is no client/session/token
getter and no route uses the coordinator. Network factories and the trusted ACK
adapter receive no SDK client. Automatic refresh is disabled for this owned
client, and its password bootstrap, local sign-out and one enrollment/adoption
attempt all require one exclusive lease. Overlapping writes are rejected.

The enrollment method calls the existing `prepareFromHttps`, which performs
exact original-bearer verification, one-attempt HTTPS delivery and isolated SDK
user/Google/company checks. A fresh operation history stream comes from the
coordinator's real Auth subscription, which has observed all writes since this
owned client was created; it does not replay pre-operation events as if they
were concurrent writes. Current actor/token and the lease epoch are checked
before the intentional write. Only then does the actual SDK `setSession` run.
Its returned/current session, exact access/refresh pair and SID, Google/Apple
identity binding and memberships must agree with the verified isolated result.

Unexpected Auth history (including A→B→A), background/dispose/sign-out during a
write, failed/unknown SDK results and timeout fence the entire owned instance.
Its network transports are closed, active HTTPS preparation is cancelled, and
no public stable actor/adoption state is exposed. A pinned SDK call can still
finish an asynchronous write internally after its client was retired; that
instance is permanently quarantined and is never reused or rolled back to an
old token. This is a logical compare-and-accept boundary for the **owned adapter**,
not a new atomic CAS primitive inside the Supabase SDK.

After confirmed owned SDK adoption, Auth/identity/membership are revalidated and
only the current successor bearer is given to the trusted possession-ACK port.
The response must be the exact existing request-bound possession schema, with
`retry_allowed:false` and `application_adoption_confirmed:false`. An unknown/lost
ACK preserves the verified owned successor and exposes only an ACK-pending state.
`retryPossessionAck` repeats this idempotent ACK after revalidation; it never
replays enrollment, password login or SDK `setSession`. Late ACK responses cannot
upgrade state after timeout/interference. A possession ACK is not evidence of
secure persistent storage or global application adoption.

Seventeen new tests exercise actual pinned SDK calls over controlled Auth HTTP
fixtures, including one real loopback HTTPS enrollment delivery composed through
SDK adoption and ACK, overlapping writes, late SDK completion after fencing,
Auth-history/background/dispose/sign-out interference, foreign envelopes,
Google/Apple/company drift, ACK loss/timeout/retry and local-only sign-out. The
existing 39 preparation/native/TLS cases remain in the same dedicated CI. There
is no local Flutter/Dart installation; analysis/execution of these Dart tests
is pending CI, not claimed as a local success. Auth/ACK are explicit fixtures;
the real TLS fixture trusts only its generated synthetic CA.

**The missing global boundary remains:** existing app Google/Face ID, password,
deep-link recovery, automatic refresh, sign-out and persistence still mutate the
shared global client outside this adapter. They must be routed through one
reviewed owner from client creation before any global guarantee is possible.
This class must not be pointed at/relabelled as that existing client. Even its
interactive password bootstrap could affect another server session under managed
single-session policy, so it must not run in production alongside an existing
session without the outstanding Auth/configuration review. Secure persistence,
restart reconciliation, an actual authenticated ACK HTTP endpoint/DB adapter,
native provider and owner iPhone checks, rate limits and deployment/restore are
still incomplete. Defaults stay OFF; no provider/grant/business data/original
signature/PDF/IPA, main merge or production change is included.

Primary sources reviewed: pinned `gotrue` 2.27.2 `setSession`, `signInWithPassword`,
session model and notification lifecycle in the official `supabase-flutter`
repository, plus current Supabase session/sign-out documentation. SDK `setSession`
awaits `getUser` before saving, which is why using it directly on an externally
mutable global client cannot supply this ownership guarantee.
