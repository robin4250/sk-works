# Own published shift Auth stream boundary — OFF candidate

The original `c9ed8fd42a584bff89863c386144eaf9793e257e` repository subscribes to
every Auth event by incrementing its read generation, including an unchanged
SDK `initialSession` replay. The dedicated CI temporarily restores that exact
original blob and observes whether the pinned SDK rejects its first normal
read. This timing regression is **not claimed reproduced until that CI passes**.
The original blob is checked before execution; the corrected file is restored
and its byte hash verified by an EXIT trap even if the baseline test fails.

The candidate handles Auth errors and completion as terminal unavailable state.
It drains queued history before reads and accepted responses, and allows only
the first `initialSession` whose actor/token matches both the construction
snapshot and the current SDK session. Other historical actor/token events still
invalidate an in-flight read, including A -> B -> A. Error/completion does not
re-enable after a later same-token event; the page must reopen a new repository.

Eight focused tests cover the actual pinned SDK replay, queued actor/token
changes, error/completion before another read/RPC, late RPC results and disposal.
Error-stream tests use an injected stream and do not claim a real SDK offline
refresh reproduction. Supabase documents that network failures are emitted on
the Auth stream and require `onError` handling:
https://supabase.com/docs/reference/dart/auth-onauthstatechange .

No local Flutter/Dart runtime was available. Shell syntax/diff checks are local;
the baseline and corrected SDK tests require dedicated CI. The fixed
`ownShiftEntryReleased = false` gate, server authorization and company selection
rules remain unchanged. Silent SDK restores without observable events, hosted
rollout, production SQL/grants and device verification remain separate.

Initial evidence: head `994f5b5450ca287b2a2edfa0a30b2ce84345c432`, dedicated
run `40684002264`, job `122801609544` succeeded. The exact original adapter
rejected after its first membership read with the actual SDK replay, restoration
hash check succeeded, both analysis steps passed and the eight corrected tests
plus twelve existing tests passed. The baseline now additionally requires the
exact Auth-state-change error text; that strengthened assertion requires its new
head's CI, rather than counting any unrelated `StateError` as the observation.
