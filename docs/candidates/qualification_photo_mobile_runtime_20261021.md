# Qualification photo mobile runtime candidate

Base: `626655ef91c7545de16b7381cac872f6605f2c67` (PR1313).
Five existing session guard files are copied by their original Git blob SHA from
`b2ea091588235cc6fcc8ec00b8b18535a1e0bcc8`; their successful CI belongs to that
guard commit, not to this new runtime.

## Unconnected composition

`QualificationPhotoMobileRuntime` defaults OFF and is not installed in any
product route. OFF construction/open/dispose performs no RPC, directory provider,
scope/lifecycle inspection or native database open. A caller must explicitly opt
in and supply authoritative actor/company/target and foreground getter/streams.
This change does not enable photo deletion.

An enabled open creates the existing fixed-token Supabase guard, reads fresh
dedicated capability/readiness, then obtains ApplicationSupportDirectory and its
canonical root. The existing store factory repeats authoritative root lookup and
confinement checks before opening its fixed database using the existing native
sqflite adapter. The existing submission repository receives the guard's scope,
scopeChanges, authorization and rpc. No arbitrary database path/opener/RPC can be
injected. The testing seam replaces only the support directory provider.

Every await around path selection/canonicalization/native open is followed by a
scope check; checks also precede path work. Token, actor, company, target,
foreground and sticky ABA invalidation remain the existing guard's responsibility.
An invalidation disposes the runtime; opening the same instance again is rejected.

Disposal revokes immediately, waits for an in-flight open to settle, then attempts
all repository/factory/RPC/native cleanup even if one cleanup fails. Late native
open results are owned before the scope check, so failure closes them too. Native
close completion is awaited. Runtime cleanup never acknowledges, deletes or clears
pending rows/files and cannot retract an already sent server commit.

## Verification and remaining gates

Local exec-server failed; no local write is claimed as evidence. All source for
this candidate was retained as raw tool content and published using GitHub tree
objects on the isolated runtime branch. No local Flutter retry was made.

The two new tests cover default OFF and dispose-before-open dependency isolation
with an HTTP client rejecting every request. They have not run locally. CI must
first analyze/format the new source and run these tests. They do not demonstrate
enabled native composition. Required further CI fixtures: fresh readiness failure
path/open=0; enabled support-root/factory/native channel wiring; token/company/
background invalidation during provider await; disposal during native open;
close failure cleanup; pending retention. Real file-backed SQLite and iPhone
lifecycle behavior remain separate checks.

No production/Auth/provider/RLS/Storage changes, actual invitation, logout,
Mac/iPhone operation, product route/help or workflow change was performed.

## CI continuation

A dedicated push-only workflow on the isolated runtime branch pins Flutter 3.47.5,
enforces the existing lockfile and verifies pubspec/lock unchanged. It analyzes
runtime and fixed guard/tools, runs runtime tests, existing native channel tests,
SDK loopback tests and the pure 171-assertion guard.

Two further runtime tests use actual pinned Supabase SDK with an in-memory
HTTP MockClient (all session/token values synthetic): readiness refusal must keep
directory lookup at zero; disposal while directory lookup is blocked must wait for
that provider and reject its late result before canonicalization/native open.
These exercise enabled rejection boundaries, not a successful native composition.
Results must be read from the current-head CI before treating them as verified.
