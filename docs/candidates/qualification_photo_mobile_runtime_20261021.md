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

## Enabled composition verification

Code commit `cc004597798991dd14ce4a6328a2c58530b2cb66` passed dedicated
[CI 39519168441](https://github.com/robin4250/sk-works/actions/runs/39519168441):
analysis, lock unchanged, runtime 4, enabled composition 1, native channel 9,
SDK loopback 4 and pure guard 171 assertions. No local exec/Flutter run occurred.

The new enabled composition uses actual pinned Supabase SDK and real loopback
HTTP, with a client rejecting all non-fixture hosts/ports. The production runtime
obtains an actual canonical temporary private directory and opens the existing
native sqflite adapter through its public mobile MethodChannel plugin binding.
The existing store factory and submission repository are composed unchanged.
Checks cover fixed actor/company/target/Bearer, capability/readiness before path
lookup, one open per runtime, preparation after local pending identity recording,
pending readback, close completion, a new runtime reading/recovering the same
request without another prepare, then background invalidation with subsequent
submit rejected before additional HTTP or SQL updates.

This proves the composition and transport boundaries represented by this fixture.
The MethodChannel handler emulates SQL rows in one in-memory Map and has no
transaction rollback engine; reopening reads that same fixture Map. It does not
prove atomic durable storage, actual SQLite execution, native platform plugin
execution, process termination/restart recovery or iPhone lifecycle behavior.
The sentinel at the fixed DB path checks only that runtime close/failure does not
delete/truncate those fixture bytes; it is not a database durability test.
The existing separate Python core checks retain their own scope and are not
substituted by this Map fixture.

Successful prepare/get and explicit recovery were tested. Explicit submit/cancel
execution was not: the only submit attempt is after invalidation and must send
nothing. No production backend, product route or UI was connected; no deletion,
real Auth/provider, Mac/iPhone or production data operation was performed.
