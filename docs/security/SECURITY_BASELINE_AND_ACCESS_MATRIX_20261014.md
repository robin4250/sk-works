# SKO セキュリティ現状・アクセス制御マトリクス（ベータ版）

確認日：2026-10-14（日本時間）。参照main：`a81da8f798da72674b8357d87374dbedb3e30d49`。
対象：[Issue #273](https://github.com/robin4250/sk-works/issues/273) の先行Aと [Issue #775](https://github.com/robin4250/sk-works/issues/775)。

2026-10-14の明示指示により専用セキュリティ更新を開始した。Issueに残る以前の「未着手・開始しない」は当時の履歴である。本文・過去の記録は削除しない。
この資料は現状監査と次の検査の基準であり、セキュリティ完成、実機合格、TestFlight配布開始、第三者レビューの完了を意味しない。

## 固定範囲と進め方

- 最新mainと既存データを保持する。復旧済みのHomeMembership、マスター権限、RLSを一括変更しない。
- 本番DBの変更は統括担当だけが行う。コード・実SQL検査・main・本番・iPhone・実機結果を別々に記録する。
- 追加契約・請求先登録を行わない。既存無料枠で可能な対策から実施し、料金条件がある機能は保留する。
- A：現状・脅威・アクセス表 → B：検証環境で否定テスト、監視と復旧 → C：本番から隔離した合成デコイ → 第三者レビューと導入ゲート。
- デコイへ実会社、給与、請求、書類、資格、LINE投稿、秘密鍵を複製しない。本番接続や認証情報を持たせない。MTDで実DBスキーマを変更しない。
- Web版は開始しない。iPhoneは既存 `com.skworks.skWorks` へRelease版で上書きし、アプリを削除しない。

## Advisorの分類（配布設定対策後）

| 検出 | グループ内件数 | 分類・対応 |
| --- | ---: | --- |
| `rls_enabled_no_policy` | 107 | 私有テーブルの直接アクセスを禁止し、必要なRPCだけで扱う設計を含む。ポリシー追加による一括開放はしない。GRANT・公開スキーマ・関数本体の境界と合わせて判定する。 |
| `authenticated_security_definer_function_executable` | 158 | 認証済み実行という性質の通知。158件すべてを新しい欠陥と扱わない。本人・会社・役割・アカウント制限の検査を各本体で確認する。 |
| `anon_security_definer_function_executable` | 0 | 初回配布設定2 RPCの不要な匿名EXECUTEを取消済み。旧関数もログイン検査は持っていたため、匿名データ漏洩が起きていたとは断定しない。 |
| `auth_leaked_password_protection` | 1 | 無効という設定上の通知。公式文書ではPro以上が対象。契約・利用可能性を確認せず有料機能を有効化しない。 |

件数はグループ内の検出件数である。「警告ゼロ」や「すべて安全」の証拠にしない。
一次資料：[RLS](https://supabase.com/docs/guides/database/postgres/row-level-security)、[Edge認証](https://supabase.com/docs/guides/functions/auth)、[パスワード保護](https://supabase.com/docs/guides/auth/password-security)。

## 現在の境界と根拠

| 境界 | 現状 | 根拠・検査の限界 |
| --- | --- | --- |
| 初回配布設定 | #997をmain・本番へ反映。正常owner/adminは維持し、匿名EXECUTEと制限中アカウントを拒否。 | `20261013191956_guard_initial_distribution_account_access.sql` と `tool/verify_initial_distribution_account_access.mjs`。実SQLロール検査成功、本番の新prosrc/ACL確認済み。保存URLと更新日時の前後照合は統括担当の記録。 |
| LINE Webhook | #998をmainへ反映。署名検証・本文上限・通信制限の更新。 | `supabase/functions/line-webhook/handler.mjs` と専用検査。本番反映・実投稿の受信結果はIssue最新記録で別確認する。 |
| グループ写真 | #999で4 Storageポリシーの `name` 参照を修正。 | 旧式は `communication_groups.name` を読んでいた。`objects.name` へ修飾し、本人/グループ/匿名/他bucketと既存restrictive境界を実SQLで検証。資料時点ではPR検査中、本番未適用。 |
| 写真の入替 | 別パスINSERT → 既存setter → 一覧再読込。 | 本番setter定義を隔離fixtureへ読み、2枚目への参照差替と旧画像保持を実SQLで確認。Storage UPDATE/DELETEを開放する必要はない。 |
| 給与・複数現場 | #993/#996の機能修正で否定ロール・確定snapshot・同時実行検査を追加。 | PR段階の証拠と本番を混同しない。担当がsource/head/CIを固定し、統括担当が前提確認後に反映する。 |
| 通信鍵 | クライアントはpublishable key、上流API鍵・service権限鍵はサーバー。 | `lib/data/supabase_backend.dart`、天気/LINE handler、Secret Scan。秘密値や利用者JWTの取得・記録は行っていない。 |
| LINEの生Webhook保存 | 本番時点の `line_webhook_events` はRLS有効。匿名/認証済みの直接SELECT・column grantとも不可。 | 本文を取得しないACL照合。restrictiveアカウント制限policyのみでpermissive policyなし。読取RPCの全会社境界は別検査であり、この結果から推定しない。 |
| 経費の承認・領収書 | 私有テーブル/RPC/会社・actor・担当者・版・保存receiptの否定検査あり。 | `verify_expense_review_allocation` / person revision / flow / receipts / cost-races の実SQL。実Storage RESTの他社/匿名/URL期限切れ・権限撤回、ログアウト時キャッシュ、サーバーの画像内容digest検証は残る。過去の本番前後digest一致を現時点の全データ保証にしない。 |

## アクセス制御マトリクス

「管理者」は名前だけで許可せず、既存の機能権限・対象範囲を必須とする。本人はログインユーザーと社員の対応をサーバーで検証する。下表は期待契約であり、すべての組合せが実JWTで合格済みという意味ではない。

| 対象・操作 | 匿名 | 一般本人 | 同社の許可された管理者・承認者 | 他社・対象外社員 | 主要経路と必要な否定検査 |
| --- | --- | --- | --- | --- | --- |
| 個人の給与明細読取 | 拒否 | 本人分のみ | 既存給与閲覧権限の範囲 | 拒否 | `payroll_statements` RLS / 保存明細RPC。会社ID・社員ID差替、直接RESTとRPC両方。 |
| 個別給与条件の保存 | 拒否 | 既存編集権限がある場合のみ | `payroll_settings_allowed` の範囲 | 拒否 | #993 read/save RPC。会社/社員/月/版差替、確定・手動給与変更、数量欠損、二重計算。 |
| 請求書読取・出力 | 拒否 | 明示請求閲覧権限の範囲 | 明示閲覧権限の範囲 | 拒否 | invoice RLS/RPC、PDFと保存snapshot。文書ID・会社差替、未確定額の出力。 |
| 請求書再計算・承認 | 拒否 | 許可なしなら拒否 | 請求管理/設定済み承認者の対象のみ | 拒否 | #996 refresh RPC / 承認RPC。再認証迂回、会社差替、対象外承認、確定snapshot、アカウント切替。 |
| 書類・資格の画像/PDF | 拒否 | 自分の対象のみ | 既存社員管理権限の対象のみ | 拒否 | private Storage/RPC。パスの会社/社員/文書差替、署名URL期限切れ、権限取消後の再取得。 |
| 通常グループの写真 | 拒否 | 参加範囲で閲覧、既存編集資格がある時だけ登録 | 既存グループ編集権限の対象のみ | 拒否 | `custom-chat-photos` + workspace/setter。他actorパス・他groupパス・MIME/サイズ・匿名・更新削除。 |
| 個別・グループチャット | 拒否 | 許可された参加対象のみ | 既存グループ権限の範囲。個別トークへの一律越境は不可 | 拒否 | `can_access_communication_group` / message・attachment RLS。group/message/file ID差替、退会後、会社間越境。 |
| LINE一覧更新・連携管理 | 拒否 | マスターでなければ拒否 | サーバーで認証されたマスターのみ | 拒否 | directory Edge/Auth/master/workspaceと連携RPC。actor/provider override、service鍵のクライアント非露出。 |
| 経費の承認・振り分け・領収書 | 拒否 | 本人申請の既存操作範囲 | 対象会社の設定済み経費承認者のみ | 拒否 | public invoker/private RPCとprivate Storage。別actor/会社/非担当/版/取り下げ/frozen consumption/再送、添付後の改変。署名URLの撤回・期限は別検査。 |
| 初回配布URLの読取/保存 | 拒否 | 一般社員は拒否 | 同社owner/admin、正常アカウントのみ | 拒否 | #997の2 RPC。匿名・社員・未所属・制限中アカウント・データ保存不変。 |

Storageの署名URLは発行後の期限内に再利用され得るため、発行時の権限検査だけで即時失効を証明しない。実URL/実ファイルの検査は検証用ファイルだけを使う。

## 先行A：確認できたことと残り

| 項目 | 確認できた根拠 | 残り・判断 |
| --- | --- | --- |
| 二次認証UI | `secondary_protected_page.dart` は画面のロック状態を持ち、background/inactiveで再ロック。`secondary_auth_lifecycle_contract_test.dart` / `secondary_auth_route_contract_test.dart`。 | 既存検査は主にソース契約。重要RPCへ直接接続した時も短命な再認証証跡が必須か、実SQL・検証用JWTで確認する。UIだけをサーバー再認証の証拠にしない。 |
| 第二パスワード試行制限 | `20260919193000_add_secure_admin_onboarding.sql` の5回/5分、bcrypt、認証必須。 | 最新本番定義・並列失敗試行・制限中アカウント・リセットAPIの再認証条件を確認する。古いmigrationだけで最新本番を安全と断定しない。 |
| 初回QR | `create-employee-invite/index.ts` のQRは招待ID・電話番号・初期passwordを含む。招待foundationに14日の期限がある。 | 短命nonce・単回消費・再発行時失効の契約は今回未確認。招待期限とAuthパスワード寿命は別。QR/初期passwordを資料・ログ・テスト成果物へ実値保存しない。 |
| セッション | SDKのログイン、actor切替検査、制限中アカウントを拒否する既存helperがある。 | 失効・logout・端末変更・削除制限中に旧JWTが残る場合のサーバー拒否を否定テストする。JWT期限内の利用を即時失効と誤認しない。 |
| 秘密・ログ | Secret Scan、天気の汎用エラー、LINEの署名/サーバー鍵分離。 | `create-employee-invite/index.ts` に上流Authエラー本文の `console.error` が残る。個人情報を含み得るためstatusだけへの縮小候補。本番ログの実内容は読んでいない。 |
| 初回セットアップ | #997の配布設定は既存account制限に接続済み。 | `mark_admin_initial_setup_step` 等の旧sourceはroleのみの検査。最新本番の制限判定は未照合。初回ログインを壊さず、必要なら対象を絞って対策する。 |
| WAF・rate | LINE上流通信制限・署名検査がある。Supabase直通の境界はRLS/RPCに依存。 | 実IP/actor単位のrate、試行制限、直接API経路での迂回拒否、監視・誤検知解除は未完了。通信timeoutをWAF完成と扱わない。 |
| バックアップ | iPhone導入前のソースバックアップ手順がある。 | 本番DB/Storage/認証の復元演習は別。実復旧試験・保存期間・権限・手動解除の記録が必要。 |

## 次の隔離検証と導入ゲート

1. 合成の会社A/B・社員本人/同社他人/他社・役割・制限中アカウントを用意する。実データ・実JWT・本番鍵を複製しない。
2. 上表ごとに許可ケースを1つ以上保ち、匿名/他社/対象外/役割変更/セッション切替を拒否する。REST、RPC、Storageそれぞれを実行し、UIだけの検査で代用しない。
3. QR期限切れ・二度目・再発行済み、重要操作の再認証未実施/期限切れ、並列試行を検査する。正常な初回登録と管理者復旧も同時に維持する。
4. 合成負荷による制限・誤検知・解除、監査ログの個人情報/秘密値除外、復旧前後の整合を確認する。費用や契約が必要なら自動導入しない。
5. source/CI/main/本番/実機の結果をIssueへ追記する。検査結果・独立レビュー・バックアップ/復旧・未解消リスクが揃ってから配布ゲートを判断する。

境界欠陥を発見した場合は、再現・対象ファイル/関数・影響・最小修正・復旧方法を記録し、同一コード/DB/認証の担当を一人に固定する。未知の状態を既知の脆弱性、静的検査を実アクセス拒否、PR完成を本番完成として記録しない。
