# 所得税税額表の永続API調査・画面接続条件

調査基準: main `ae80103101f303291cc84c6094b02df5bcf3b15d`。この文書は接続設計であり、所得税資料を保存・検証・給与へ適用するAPIや画面は実装していない。本番DB・Storage・Auth・既存画面は変更していない。

## 現状と再利用範囲

| 既存箇所 | 確認できた動作 | 所得税登録への境界 |
| --- | --- | --- |
| `lib/features/payroll/domain/company_rate_contract.dart` の IncomeTaxTableReference / Registry | 暦年、月額・日額・賞与・電子計算の種類、適用期間、PDF URI、資料hash、3つの検証・承認状態。期間重複拒否、旧年度・旧検証状態保持、開始日で計算準備済み資料を選択 | 純粋モデル。PDF解析、永続保存、承認者認証、信頼できるhash生成を行わない |
| `test/income_tax_table_registry_test.dart` | 新年度境界、未検証資料非選択、他社資料共有条件、重複・期間変更拒否のテスト | APIや実給与の接続テストではない |
| `lib/features/payroll/individual_payroll_settings_page.dart` | income_tax_monthly を月額入力・保存 | 税額表年度の登録・計算は未接続。固定金額を突然消さず、明示移行までは保持する |
| `supabase/migrations/20261008200018_paid_leave_wage_contract.sql` | 給与控除計算でsettingsのincome_tax_monthlyを参照 | 税額表ID／版／行を読み込む経路は未確認 |
| `lib/features/people/company_submitted_document_repository.dart` | company_required_documentsへ任意資料を登録、company-required-documentsへアップロード、10分signed URLを発行 | 添付は単一path。差替成功時に旧pathを削除するため、税額表旧版保持へそのまま流用できない。暦年／種類／適用期間／hash／計算ルール検証のAPIはない |
| `lib/features/people/worker_document_repository.dart` と `lib/features/operations/vehicle_route_repository.dart` | 他用途のPDF対応Storageアップロード・添付参照 | 対象者・車両の権限と更新・削除用途が異なる。所得税資料の保存先へ流用しない |

lib、supabase/functions、supabase/migrationsを所得税／源泉徴収／税額表／income_tax_table／withholdingで調査し、税額表を永続管理するtable・RPC・Storage専用bucket・検証承認APIは見つからなかった。稼働中DBの全schemaや外部サービスはこの調査対象外。APIの存在を推測して呼び出すadapter、架空の保存成功を表示する画面は追加しない。

## 最小限の永続契約（未実装案）

1. 会社単位の登録一覧読取。table ID、会社ID、暦年、種類、適用開始／終了、version、正式情報元、immutable資料identity（Storage object/versionまたは正式URL＋bytes hash）、登録者・日時、検証結果・担当者・日時を返す。未登録と取得失敗を分離。
2. 会社管理者のPDF登録。bytesを新objectへ登録後、サーバーが会社・object存在・PDF形式・サイズ・hashとmetadataを照合し、version付きmetadata保存を行う。登録時の正式資料／計算ルール／共通承認はすべて未検証。失敗時は結果を再照会できるrequest IDを使用し、成功不明の自動再送で重複を作らない。
3. 年度・種類・期間の重複防止をDB transactionでも検証する。PDF訂正は新しい資料identityと明示的な版・日程変更で扱い、旧資料・既存給与が参照した版を保持する。添付差替時に旧PDFを削除しない。
4. 正式資料検証と計算ルール検証は分離。年度・適用期間・種類・実資料内容・公式情報元を照合した信頼できる検証結果から更新する。通常の会社管理者のチェックボックスでofficialDocumentVerifiedやcalculationRulesVerifiedを直接trueにしない。
5. 共通データ化は別の検証・公開承認経路とする。利用者の登録だけで他社一覧や給与計算に公開しない。commonDataApprovedの更新権限・検証証跡・失効時の扱いを決めるまでは共通公開操作を設けない。
6. PDF閲覧はimmutable Storage locatorから短期限signed URLを都度発行する。期限付きURLを永続的な資料IDや登録URIとして保存しない。正式URLの資料が差し替わった場合もbytes hashが変われば同一資料の検証状態を引き継がない。
7. 読取adapterは必要字段と検証状態を確認してからIncomeTaxTableRegistryへ変換する。Storage locatorを純粋モデルのhttps PDF URIへ変換する形式は確定が必要。signed URLの更新で資料identityが変わる設計にしない。
8. 実給与の選択基準日・種類と版IDを計算transactionで確定し、税額表・検証version・使用行／計算ルールを給与snapshotへ保存する。新年度登録時点では給与を変更せず、適用開始日に条件が整ったものだけ選択。資料が無い／期限切れ／未検証なら旧表へfallbackしない。

Storageの会社管理者アップロード・会社内閲覧と検証担当の読取範囲、metadata直更新禁止、版参照中objectの保持をDB ownerが設計・実際の権限で検証した後にUIを接続する。既存bucketのACLや他用途のoriginal_verifiedフィールドを税額表の公式検証に読み替えない。

## 最小の画面案（永続契約確定後）

- 一覧: 暦年／種類／適用期間／情報元／資料検証・計算準備の状態を表示。次年度事前登録と旧年度を同じ一覧に残す。
- 登録: 暦年・種類・開始日・終了日・PDF・公式情報元を入力。期間の終了日を含むかを画面で明記し、RegistryのendsBeforeへ統一する。入力は端末タイムゾーンのDateTimeへ暗黙変換しない。
- 確認: PDFと年度・期間・種類を本人が見直し、確認して会社内の未検証資料として登録。通常の利用者には検証済みや共通公開へ変更するtoggleを出さない。
- 詳細: 旧年度を含む資料版・検証証跡・登録者／検証者・日時を確認。資料の正式性と計算準備を区別する。
- 選択表示: 指定した暦日のRegistry.selectを表示する。これはプレビューであり、給与を自動更新したという表示をしない。

公式情報の新年度自動検出・取得、PDF解析、国税庁税額表の計算ルール、会社を超えた検証共通化は別の未接続項目。永続APIがない現在はUI保存・新年度自動切替を完成扱いしない。
