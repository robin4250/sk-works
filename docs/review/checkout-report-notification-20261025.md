# 退勤後の日報登録通知 — 専用target再開候補

原典main `1f05f3b2cb766dc7b978145f8ebd98a6002f92ea` の通知3ファイルをsnapshot `10f0480` へ保存。依存はstage1 PR1383 (`e5db2c`、後続fixture修正17d39f0はclass/API維持) のcheckout_report_resume_repository/action。DB・globalgate・DailyReportPage本体・Auth製品コード・共有翻訳は変更しない。backendはcommon担当、stage2gateはmonth担当。

## 契約と導線

専用action `checkout_report_registration` とreport UUIDだけを受け付け、既 `group_report_saved` / get_source_notification_targetへ偽装しない。新reader `read_checkout_report_registration_notification(p_report_id)` のサーバー認可済みenvelopeだけを採用する。actor_id=現在本人、report_id=通知target、schema1、rollout、DATE、会社/worker/場所/source pair、state6種、blocking整合、MD5 fingerprint32字をstrict検査する。fingerprintは鮮度確認にのみ使い権限証にしない。

既AppNotificationRepositoryで新actionをbusiness targetへ追加し、一覧の状態を専用readerから補完する。既読でもpendingは未完カウントのまま、resolved=trueだけregistrationタスク完了。無効policy/取得失敗はunknownであり未登録解消と扱わない。既attention mapper/dedupを再利用し、新しいqueue/tableや未読schemaは追加しない。NotificationsPageはリンク読取権限を先に再確認し、失敗したリンクを既読にしない。

専用pageでは対象reportの入力不足/報告者署名不足、現場責任者待ち、署名済み給与・勤怠投影未確認、source conflictを別表示する。source conflict/report不明/署名済み投影待ちではeditorを開かない。入力/報告者サイン未完と責任者待ちだけ、stage1 loadDay/revalidateにより会社・worker・日付・現場/route・report ID・exact出退勤pairを照合し、通常DailyReportPageへ再開する。restricted gate modeへ切り替えたり確定給与を編集する機能を新設しない。

stage1 targetは同日の同じ勤務先の複数訪問を集約するため、通知pairがその集合に残っていることを前後確認し、画面anchorだけを通知のpairへ合わせる。group先頭の別訪問へ飛ばず、人工・給与数量を追加しない。DailyReportPageへのroute callbackは、stage1の正規action/revalidationを使いながら最後のhandoffでも通知sessionを確認するために置く。同pageの既source-anchor引数をそのまま使用する。

元sessionのactor/SID/tokenを保持し、AuthStateのemitted session identityを捨てない。same-user SID A→B→Aやsignoutはsticky失効、背景化/dispose/遅い旧responseで旧targetを復元しない。RPC不在/他者target/他社source/型不正はunavailableとし、unscoped table fallbackや新規日報自動作成を行わない。

## backendとの確認済みshape

共通担当 `checkout-report-authoritative-backend-20261025/docs/candidates/checkout_report_registration_reminders.sql.review-only`:

`{schema:1,actor_id,report_id,enforcement_enabled,effective_from,resolved,items}`

各item: `{company_id,worker_id,work_date,site_id,route_assignment_id,report_id,source_clock_in_id,clock_out_id,registration_state,blocking,scope_fingerprint}`。

blocking states: report_missing / source_conflict / report_input_incomplete / reporter_signature_missing。非blockingの未解消理由: reporter_saved_waiting_supervisor / signed_projection_unverified。resolved時items=[]。serverは現通知recipient・現member・本人worker/source/rolloutを認可し、通らない時42501。clientは自由なpermission flagを作らない。

## 検証候補・統合依存

専用repo試験はUUID専用route、既読でもpending維持→reader解消時だけcompleted、6 state、resolved対disabled、他actor/report/不正source、Bearer固定・1回RPC/no fallback、実SDK defaultasync SID ABAを検査する。widgetはexact report再開・stage1前後revalidate、同日複数訪問の通知pair anchor、責任者待ち/投影待ち/競合の別扱い、他社/入れ替わったreport拒否、unknown/ヘルプ、async SID ABAでの消去を検査する。

`git diff --check` 成功。local Flutter禁止につきanalyze/testsは未実行。rootはPR1383 sourceを含むbase/合成branchへ載せ、少なくとも次のremote検証を行う:

```sh
flutter analyze lib/features/notifications/checkout_report_notification_repository.dart lib/features/notifications/checkout_report_notification_page.dart lib/features/notifications/app_notification_repository.dart lib/features/notifications/notification_target_policy.dart lib/features/notifications/notifications_page.dart test/checkout_report_notification_repository_test.dart test/checkout_report_notification_page_test.dart
flutter test test/checkout_report_notification_repository_test.dart test/checkout_report_notification_page_test.dart --reporter expanded --timeout 30s
```

既通知routing/attention/target-policy試験とstage1 resume試験も保持して確認する。backend未適用、rollout未有効、実通知/本人端末での日報再開は未確認。通知既読・reporter登録・責任者署名・給与投影を一括して完了にしない。

## rootへ渡す「？」/翻訳キー

共有翻訳は統合担当へ集約するため未編集。以下が追加user-facing key（既存の使い方/閉じる/再読み込みは再利用）。

| Japanese key | Suggested English |
| --- | --- |
| 退勤後の日報登録 | Daily report after checkout |
| 退勤後の日報通知について | About report registration reminders |
| 対象の日報を再開 | Resume this report |
| 対象の日報を確認できません。管理者が勤務原本を確認してください。 | Report unavailable. Ask an administrator to verify the original work record. |
| 日報と退勤の対応確認が必要です。管理者に確認してください。 | The report and checkout need reconciliation. Ask an administrator. |
| 日報の必須項目が未登録です。 | Required report fields are incomplete. |
| 日報の報告者サインが未登録です。 | The reporter signature is missing. |
| 報告者の登録は完了しています。現場責任者のサイン待ちです。 | Reporter registration is complete; waiting for the site supervisor signature. |
| 日報は署名済みです。給与・勤怠への反映確認が必要です。 | The report is signed; payroll and attendance projection still need verification. |
| 日報の状態を確認できません。 | Report status is unavailable. |
| ログイン状態が変わりました。通知を開き直してください。 | Your session changed. Reopen the notification. |
| 通知の日報を確認できません。対象・権限・接続を確認してください。 | Notification report unavailable. Check the target, permissions and connection. |
| 日報の状態が変わったか、対象を確認できません。再読み込みしてください。 | The report changed or its target is unavailable. Reload it. |
| 日報登録通知の提供状態を確認してください。未登録が解消したという意味ではありません。 | Check report-reminder availability. This does not mean the report is complete. |
| この日報の登録に関する未完項目はありません。給与への反映完了を示すものではありません。 | No outstanding registration items remain for this report. This does not confirm payroll projection. |
| 通知を既読にしても日報の未登録は解消しません。保存済みの退勤と同じ日・勤務先の日報を再開します。もう一度出勤・退勤する必要はありません。報告者の登録、責任者のサイン待ち、署名済みの給与反映待ちは別の状態です。給与への反映済みとは、この通知だけでは判断しません。 | Reading a notice does not complete the report. Resume the report for its saved checkout date and workplace; do not clock in or out again. Reporter registration, supervisor signature and signed payroll projection are separate states. This notice alone does not prove payroll projection. |


## 専用CI追送と最新API再照合

`.github/workflows/checkout-report-notification.yml` はbranch制限なしのpull_request path filter＋任意dispatchを持つ。Flutter3.47.5固定、contents read、checkout credential非永続。本番secret/URL/JWTを渡さない。対象source/tests analyze、新規reader/page tests、既attention/notification/正規stage1 resumeの14 regression filesを別stepで実行する。UI側はstage2gateをimportせず、stage1 PR1383最新bc607を含む親だけで独立して検証できる。

backend latest `bee37e7` のnotificationreader/gateitemを読取で再照合。clockout/report認可が `coalesce(out.daily_report_id,in.daily_report_id)` に改善されても応答7/12keys・state6種・MD5 fingerprint32は変わらず、このclient parserと一致する。DB本体の編集は0。

翻訳表の16新キーはJapanese/Englishの意味を再点検し、read state、reporter署名、site supervisor署名、payroll projectionを分けたままrootへ渡す。翻訳辞書本体はroot所有のため変更しない。

YAML構文/branch制限無し/contents read/6 stepsとgit diffチェックは成功。localFlutter/analyze/testsは引続き未実行で、専用remoteCI成功とはまだ扱わない。
