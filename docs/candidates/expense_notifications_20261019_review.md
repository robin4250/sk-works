# 経費通知：未適用のsource候補と隔離検証

基準 local `040a00fd42d7b9b42084a11b191f03ac2d635591`。本候補は本番未適用で、migrationではない。
SQLは `expense_notifications_20261019.sql.review-only`、検証は `tool/verify_expense_notification_candidate.mjs`。
既存の申請・承認・領収書・再計算関数、既存テーブルの列・RLS・ACLを変更しない。
既存金融snapshotの符号変更、給与精算接続、実通知配信、バックフィルは行わない。

## イベントと宛先

| 保存元 | 送る時点 | action_key / action_id | 宛先 |
| --- | --- | --- | --- |
| `private.expense_claims` | AFTER INSERTだけ | `expense_review_request` / claim UUID | 同会社owner/admin、および同会社manager/viewerで現在の経費承認担当に設定された人。重複所属行でもDISTINCTで1人1件 |
| `private.expense_review_confirmations` | AFTER INSERT、command/actionとresultがapproveの場合だけ | `expense_review_completed` / confirmation command UUID | claimの`created_by`に保存された申請者Auth UUID。現在の同会社所属とAuth user存在も確認 |

`applicant_id`はworker UUIDなので通知先として使わない。単なるmanager/viewer、他会社の管理者、一般社員へ管理者通知を広げない。
owner/adminの設定閲覧権限と、選択された担当者の審査権限は既存`expense_review_access`と同じ役割集合で扱う。
通知は確認・閲覧への入口で、受信自体が承認操作の権限を追加するものではない。自己申請の承認制約は既存保存関数に残る。

本文は固定文だけで、申請者名・金額・申請内容・メモ・領収書path・署名・給与情報を含めない。
既存`private.enqueue_notification`をそのまま利用してアプリ内通知行を作成する。端末pushやメール到達を保証しない。
通知対象のアカウント状態を他人として偽装して確認せず、読取時に本人の`account_access_allowed()`を再評価する。

新規claim INSERTとcommand UUID主キーのconfirmation INSERTが重複防止の根拠。同じ固定ID/commandの再確認は既存receiptを返し、triggerを再発火しない。
別commandで改めて有効なapproveを確定した場合は別イベントとして扱う。reject/edit・途中dialog・取消では完了通知を作らない。
既存請求額の変更とは切り離し、通知生成失敗は例外を握りつぶさず保存transaction全体をrollbackする。この保存可用性への追加依存は配備前の影響レビュー対象。

## 通知IDだけからの読取

新RPC候補 `public.expense_notification_target(p_notification_id uuid)` はpublic invoker wrapperからprivate definerへ委譲する。
新入口はauthenticatedだけ、trigger関数はpublic/anon/authenticated実行を剥奪。固定search_pathとschema修飾を使用する。
既存public/private関数の定義・権限は置換しない。

1. ログイン・現在のaccount availabilityを確認。
2. 保存通知のID・recipient=本人・許可action・action_idを照合し、現在の同会社所属を確認。
3. requestは同会社claim ID完全一致、withdrawn拒否、現在のreview/configure権限で現在の申請を返す。
4. completedは同会社confirmation command UUID完全一致、approve、現在のclaim created_by=本人、immutable resultのclaim/company/creator一致を確認し、**確定当時の結果**を返す。
5. 不一致は42501。会社・worker・claim overrideを入力できず、設定画面や別の一覧へのfallbackはない。

返却は契約済みの6外側keys `notification_id/action_key/action_id/company_id/claim_id/claim`。
claimは`id/company_id/applicant_name/incurred_on/submitted_at/description/amount_yen/approval/allocation/counterparty_name/settlement_method/settlement_month/reviewed_at/review_memo/revision`の15項目だけ。
Auth/worker ID、履歴command、領収書、署名、backend secretを返さない。完了通知を現在の申請状態として表示しない。
requestのsettlementは同じclaim revisionでapproval_currentの場合だけ付加する。

統合client候補はread-only summary＋refreshを接続。requestは現在内容、completedは確定時のimmutable receiptとして表示する。
厳密な同じparserでID/会社/申請/版/日付/金額/状態を検査し、requestの業務状態だけを要対応集計へ接続する。
読取不能・旧schema・無権限・不正応答はunknownとなり、pendingと断定しない。completedは履歴案内として扱う。
actor切替/ABA/stream error/背景移行で旧表示を破棄し、同じactorでの再表示時も再読取する。
通知から承認・振分け・精算を自動実行しない。管理者の判断画面への直接接続は未完で、現在は対象summaryから経費一覧で操作する案内を表示。
本SQLだけ、または未適用のclientだけでは通知発行・受信が成立しない。

## 実行した隔離検証

既存PGlite **0.3.14** cacheと`setupExpenseCostFixture`を再利用。依存追加・SDK取得は0。
既存expense原本・実submit/atomicconfirm関数と、保存sourceの実enqueue/table/RLS定義を使用した。
会社・利用者・請求書・署名markerは全て架空で、外部接続・本番query・実通知は0。

```sh
node tool/verify_expense_notification_candidate.mjs /workspace/scratch/0c056373e74e/sko-notification-integration/tool/security/fixture_dependencies/node_modules/@electric-sql/pglite/dist/index.js
```

最終結果は **exit 0、14 boundary groups PASS**。

- 既submit/confirm/enqueue/invoice/payment計算関数の`pg_get_functiondef`を適用前後で完全比較。
- 同会社の正当な宛先集合、他会社・非担当manager・worker UUID誤用の排除。
- 固定申請IDと固定confirmation commandの同内容再確認・内容違い拒否、通知重複0。
- 保存通知のrecipient/current company/current role/action再認可、欠落・他人・匿名・権限取消拒否。
- approve完了1件、reject/edit/失敗した確定には完了通知0。
- 後日の編集後も完了通知は当時の金額・内容、申請通知は現在の内容。
- 申請を含むtransaction rollbackで申請・通知とも0。
- fixtureでenqueueに失敗を注入し、承認・精算設定・confirmation receipt・通知が全てrollback。
- 既取下げAPIでwithdrawnにしたrequestを拒否。
- 確定済み金融snapshotが無関係な通知操作で不変、署名markerがsummaryへ漏れない。
- 固定本文の非PII、summary whitelist、保存通知の本人RLS、新入口ACL。
- 所属削除・account拒否で古い通知リンクを拒否、給与明細生成0。

追加fixture作成時にwithdrawn単独UPDATEの既制約違反、customersのfixture列名違いを検出した。既制約を変更せず、既取下げAPIと正しいfixture列で修正した。失敗した試行を成功とは数えない。
`node --check`と`git diff --check`も成功。Flutterは本担当では実行していない。

SQL SHA-256: `e369dc553edd5f78a2c1ed10bc4f2e5d693a00e35db2c3c1b903bdb449f16a05`。

## 未検証と配備前条件

- Supabase CLI/psql/Postgres server実行binaryが無く、実PG17・同時接続race・CLI advisorは未実行。PGliteの合成auth・簡略fixtureを本番RLS/JWT/GoTrue/DataAPI検証へ読み替えない。
- CLI migrationコマンドを実行できないためmigration名は作らず、このreview-only文書配下に保存した。将来CLIの`--help`でdiscoverしてから適切なmigrationへ包装する。
- candidateは既存objectの存在と新nameの未使用を確認するが、全本番body/owner/ACL/trigger/column差分を照合する配備guardではない。実環境との差分、通知表の更新列権限、schema exposure、必要grant、当日依存を読取で確認する必要がある。
- 新trigger追加で既保存transactionに新しい失敗要因が増える。負荷・lock順・複数接続の同時fixed command・受信者所属/権限取消race・失敗時復旧を隔離実PGで確認する。通知失敗だけ無視して保存を通す変更は別仕様。
- 既通知の履歴や既申請へ通知を遡及生成しない。旧式approve/allocate経路からの完了通知は本候補の対象外で、atomic confirmation INSERTに限定。
- 適用承認、backup/実archive隔離復元、現管理者・Auth/provider・RLS/ACL保持、rollback/停止条件の実証は未完。この候補作成は本番適用の承認ではない。

Supabase skillを再読済み。公式[Changelog](https://supabase.com/changelog)（2026-10-18確認、直近のTLS変更等に本候補のtriggerを変更する内容なし）、[Triggers](https://supabase.com/docs/guides/database/postgres/triggers)、[Functions](https://supabase.com/docs/guides/database/functions)を確認した。Markdown URL取得はツールのcontent-type制約で失敗したためHTMLへ切替えた。

Client follow-up: the request notification remains pending when approval exists but allocation is unallocated or no settlement method is saved. Read status alone and approval alone do not establish completed allocation. This does not change claim approval or settlement records.
