# Standalone signed-readback deadline evidence

Baseline: main `d7c105d5a4d6e4636092a5fbe674a9c2cc28256b`. The final regression test and unchanged byte store were copied into a disposable tree with that commit's receipt module (`git show`), then `node --test tests/archive-readback-monotonic-deadline.test.mjs` ran. No source in the working tree was reverted and no database/service was contacted. Exact RED output below has only the temporary path normalized. All five cases failed because a late valid result was accepted, not because of missing dependencies or fixture setup.

```text
✖ synchronously late restore cannot reach signing while timers are starved (44.79942ms)
✖ synchronously late valid signer result is unknown, rejected and never retried (35.280842ms)
✖ verifier rejects a valid fresh signed response returned after a synchronous transport stall (32.738762ms)
✖ deadline elapsed before the first operation microtask refuses callback work (32.330335ms)
✖ each successful or rejected operation clears its one owned deadline timer exactly once (32.579251ms)
ℹ tests 5
ℹ suites 0
ℹ pass 0
ℹ fail 5
ℹ cancelled 0
ℹ skipped 0
ℹ todo 0
ℹ duration_ms 271.064574

✖ failing tests:

test at ../../../..<disposable-baseline-tree>/tests/archive-readback-monotonic-deadline.test.mjs:30:1
✖ synchronously late restore cannot reach signing while timers are starved (44.79942ms)
  AssertionError [ERR_ASSERTION]: Missing expected rejection.
      at async TestContext.<anonymous> (file://<disposable-baseline-tree>/tests/archive-readback-monotonic-deadline.test.mjs:34:2)
      at async Test.run (node:internal/test_runner/test:1409:7)
      at async startSubtestAfterBootstrap (node:internal/test_runner/harness:387:3) {
    generatedMessage: false,
    code: 'ERR_ASSERTION',
    actual: undefined,
    expected: /readback unavailable/,
    operator: 'rejects',
    diff: 'simple'
  }

test at ../../../..<disposable-baseline-tree>/tests/archive-readback-monotonic-deadline.test.mjs:37:1
✖ synchronously late valid signer result is unknown, rejected and never retried (35.280842ms)
  AssertionError [ERR_ASSERTION]: Missing expected rejection.
      at async TestContext.<anonymous> (file://<disposable-baseline-tree>/tests/archive-readback-monotonic-deadline.test.mjs:42:2)
      at async Test.run (node:internal/test_runner/test:1409:7)
      at async Test.processPendingSubtests (node:internal/test_runner/test:974:7) {
    generatedMessage: false,
    code: 'ERR_ASSERTION',
    actual: undefined,
    expected: /readback unavailable/,
    operator: 'rejects',
    diff: 'simple'
  }

test at ../../../..<disposable-baseline-tree>/tests/archive-readback-monotonic-deadline.test.mjs:45:1
✖ verifier rejects a valid fresh signed response returned after a synchronous transport stall (32.738762ms)
  AssertionError [ERR_ASSERTION]: Missing expected rejection.
      at async TestContext.<anonymous> (file://<disposable-baseline-tree>/tests/archive-readback-monotonic-deadline.test.mjs:51:2)
      at async Test.run (node:internal/test_runner/test:1409:7)
      at async Test.processPendingSubtests (node:internal/test_runner/test:974:7) {
    generatedMessage: false,
    code: 'ERR_ASSERTION',
    actual: undefined,
    expected: /readback unavailable/,
    operator: 'rejects',
    diff: 'simple'
  }

test at ../../../..<disposable-baseline-tree>/tests/archive-readback-monotonic-deadline.test.mjs:53:1
✖ deadline elapsed before the first operation microtask refuses callback work (32.330335ms)
  AssertionError [ERR_ASSERTION]: Missing expected rejection.
      at async TestContext.<anonymous> (file://<disposable-baseline-tree>/tests/archive-readback-monotonic-deadline.test.mjs:56:101)
      at async Test.run (node:internal/test_runner/test:1409:7)
      at async Test.processPendingSubtests (node:internal/test_runner/test:974:7) {
    generatedMessage: false,
    code: 'ERR_ASSERTION',
    actual: undefined,
    expected: /readback unavailable/,
    operator: 'rejects',
    diff: 'simple'
  }

test at ../../../..<disposable-baseline-tree>/tests/archive-readback-monotonic-deadline.test.mjs:60:1
✖ each successful or rejected operation clears its one owned deadline timer exactly once (32.579251ms)
  AssertionError [ERR_ASSERTION]: Missing expected rejection.
      at async TestContext.<anonymous> (file://<disposable-baseline-tree>/tests/archive-readback-monotonic-deadline.test.mjs:70:2)
      at async Test.run (node:internal/test_runner/test:1409:7)
      at async Test.processPendingSubtests (node:internal/test_runner/test:974:7) {
    generatedMessage: false,
    code: 'ERR_ASSERTION',
    actual: undefined,
    expected: /readback unavailable/,
    operator: 'rejects',
    diff: 'simple'
  }

```

GREEN on the changed module: `node --test tool/security/notice-archive-candidate/tests/archive-readback-monotonic-deadline.test.mjs tool/security/notice-archive-candidate/tests/archive-readback-receipt-candidate.test.mjs` passed all 17 tests, zero failures/skips. This includes five new deadline/cleanup regressions and the 12 existing receipt tests. The test uses real temporary-filesystem retained/read-back opaque bytes and real Ed25519 signatures. Filesystem preparation completes before timing starts. Actual 25ms synchronous stalls starve timer callbacks; the target stage monotonic clock is advanced deterministically so an unrelated OS pause cannot cause the signer-stage test to stop before signing. The separate wall clock stays fixed. The bounded budget starts on entry to the helper, before scheduling its first operation microtask.

The fix checks a monotonic absolute deadline before work, after awaited restore/fetch/sign, immediately before signing, after receipt verification and before returning a settled result. Both successful and rejected operations clear exactly their one owned timer in the helper finally block; the regression checks distinct timer handles and one clear each. A signer already called may have completed externally even when its result is rejected; no retry, cancellation, custody, provenance or source-release guarantee is inferred. No original byte objects are deleted or unpinned.
