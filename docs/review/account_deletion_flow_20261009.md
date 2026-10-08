# Account deletion full-flow audit — 2026-10-09 JST

Reviewed repository main `a2a0ad26cebfbcc39ec99fe49f8b78d4ceb6c202`, including the unchanged deployment-source archives from PR #751 and the processor verification added by PR #752. This is a repository/source audit, not a new inspection of current production configuration. No intake, deletion, notification, credential, Auth, or production database operation was invoked.

## Conclusion

The remaining work is **not only running more tests**. Handler and orchestration code exists, but record classification/retention, an app-facing deletion entry, and real lifecycle acceptance remain unresolved. Do not enable the feature from the offline test result.

| Area | Source evidence | Remaining work |
|---|---|---|
| Release guards | Archived `account-deletion/intake_configuration.mjs`: `intakeReleaseVerified = false`; worker `account-deletion-worker/index.ts`: `lifecycleReleaseVerified=false` | Preserve both false until separate acceptance and release decision; environment switches alone do not activate them. |
| Official documents | Both archived policies set `officialDocumentRetentionFinalized: false`. `worker.mjs` and `storage_erasure.mjs` block worker-documents, qualification-certificates, employee-onboarding-documents in the generic erasure plan. | Implement and review record-specific classification/retention and inventory completeness before treating those records as deletable. This is an actual implementation/policy gap, not an unexecuted unit test. |
| App entry and status | No account-deletion, account deletion, 退会, or アカウント削除 references found anywhere under `lib` at the reviewed commit. | Provide explicit app UI/route for intake, confirmation, disabled/readiness state and request status, without claiming an accepted request is a completed deletion. A separate unseen external UI is not assessed. |
| Business retention | Archived RPC snapshot includes lease/policy checks, retained-actor conflict checks, fingerprints and receipts in `preserve_account_deletion_company_records`. | Isolated DB fixtures must establish payroll, invoice, signed daily-report and history retention through actual Auth deletion/cascades. A snapshot of definitions is not end-to-end evidence. |
| Authentication and access | Handler enforces authentication/session/AMR guards; assembled worker has deployment, subject-access and pre-mutation probes. | Verify actual JWT/session invalidation, DB barriers/RLS, edge endpoints, stale sessions and cross-company access in an isolated environment. Keep service-only execution privileges. |
| External provider | Google credential/revocation/evidence adapters exist and unknown provider adapters fail closed. | Verify configured encryption/provider revocation and retries with test identities. No production credential values were read. |
| Storage and Auth | Storage ownership, reviewed-plan and absence checks; Auth server permit and post-deletion absence checks exist. | Verify complete file inventory, signed/public URL access after erasure, ownership boundaries, lease-loss and concurrency using disposable accounts/files. |
| Completion mail | Support Gmail sender adapter exists; missing OAuth configuration stops delivery. | Verify configuration and test delivery/idempotency. No email was sent and configuration readiness is not inferred from source. |

## Executed verification

- `node --test docs/recovery/account_deletion_source_20261008/verification/guard_tests.mjs docs/recovery/account_deletion_source_20261008/verification/processor_tests.mjs`: **183 passed, 0 failed, 0 skipped**. These repeat the preserved handler/processor suites once on the reviewed main and use synthetic injected ports. Their zero-network audit passed. They do not validate real destructive adapters, deployed ACL/RLS or email delivery.
- `bash tool/pre_device_release_gate.sh`: passed available dependency-pin, client-secret, destructive-command, migration-file and shell-syntax checks. **Flutter/Dart SDK absent; analyze/test skipped**. This result is not a Flutter build or real-device gate completion.
- `bash -n` on device-day, release gate, source-backup and device runner: passed.
- No production changes, flag changes, app/Auth/RLS edits or account deletion performed.

## Release runner review

`tool/device_day.sh` runs the pre-install source backup first, then local gate, iOS preparation, device preflight and `run_ios_device.sh`. The device runner builds `--release`, checks `com.skworks.skWorks`, installs with devicectl and launches that same bundle. It does not uninstall the existing application. Mac/Xcode signing and physical-device execution remain required; this environment cannot confirm an iPhone installation.

One remaining instruction defect: the final success text in `tool/run_ios_device.sh` recommends `tool/run_ios_device_debug.sh`. Remove that suggestion in the release-script lane to honor the user's Release-only instruction. This audit intentionally does not modify the runner.

## Safe next implementation order

1. Resolve and implement the official-record classification and retention rules; keep payroll/invoice/signed-report history protected.
2. Add the app-facing flow/status with disabled-state behavior while fixed release guards remain false.
3. Build disposable isolated lifecycle fixtures around actual RPCs and adapters, including access loss, retained history, retry/concurrency and erasure evidence.
4. Establish sender/provider/deployment readiness without exposing secrets, then execute isolated acceptance.
5. Only after all acceptance criteria are evidenced, make a separately reviewed enabling decision. TestFlight upload additionally waits for the user's Apple Developer company registration; local Release installation is a separate path.
