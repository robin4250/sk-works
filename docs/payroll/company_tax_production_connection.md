# 会社共通税率・所得税資料の本番接続

2026-10-10、main `d7a4e48bc11baaf23edf6bb84906581cd2d43e4d` の既存SQLを導入した。料率画面の「この会社では料率設定をまだ利用できません」は、読出しRPC未導入が原因だった。

## 適用内容

| 本番のmigration | 対応する既存source |
| --- | --- |
| `20261010013333_company_payroll_rate_registry_with_viewer_read` | `20261009151946_company_payroll_rate_registry.sql` + `20261009183439_company_payroll_rate_viewer_read.sql` |
| `20261010013430_company_income_tax_registry_pdf_with_viewer_read` | `20261009155006_company_income_tax_table_registry.sql` + `20261009155952_company_income_tax_private_pdf_storage.sql` + `20261009184013_company_income_tax_viewer_read.sql` |

各組は既存SQLを順に連結し、末尾に `NOTIFY pgrst, 'reload schema'` を付け、MCP apply_migrationで適用した。source SQLの変更・二重migration追加はない。本番ledgerのversionは元ファイル名と異なるため、未適用と誤認して再実行しない。全migrationの一括push、ledgerの自動repairは実施していない。

導入前に対象schema/bucketが存在しないこと、会社・会員・アカウント制限関数・Storageの操作別判定とRLSを確認。既存の会社・会員・給与・手当の行や関数は変更していない。新しいprivate schemaと専用bucket用ポリシーを追加した。新しいStorage制限は他bucketを通す。実料率・会社条件・PDFは登録していない。

## 検証

PGlite 0.5.8の使い捨てDBで以下の既存5スイートが成功した。合成データは本番へ送っていない。

- `verify_company_payroll_rate_registry.mjs`: 保存、適用条件、版競合、監査失敗時rollback、会社削除時の履歴保持。
- `verify_company_payroll_rate_viewer_read.mjs`: 同一会社viewer閲覧、書込拒否、他社・未登録・制限アカウント拒否。
- `verify_company_income_tax_table_registry.mjs`: PDFメタデータ、期間重複、版・監査、検証済み資料の選択条件。
- `verify_company_income_tax_pdf_storage.mjs`: 専用private bucket、操作別アクセス、上書き・削除・一覧拒否、他bucket維持。
- `verify_company_income_tax_viewer_read.mjs`: viewerの登録済み現在/旧版PDF閲覧、未登録PDF・書込拒否。

`tool/verify_company_tax_connection.sql` は本番で利用できる読取専用確認。RPC存在/ACL、8 private tableのRLS/直接アクセス不可、PDF bucket/7 policies、JWTなしの読出し拒否を検査する。実データを表示・変更しない。保存・PDF実体転送の成功や完全なpolicy定義一致までは証明しないため、上記分離試験と併用する。

実機Releaseでは税率画面の再読込で会社条件・健康/介護/厚生年金等の設定欄と管理者編集導線が表示された。実機での実料率保存やPDF uploadは未実施。DB advisorsは新規WARNなし。新規8 private tableのRLS/no policyは直接アクセス拒否の設計どおり（[Supabase説明](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy)）。既存の別機能WARNは今回変更していない。

## 利用可能範囲と残件

管理者は会社条件・料率を手動設定でき、viewerは同一会社の閲覧のみ。所得税資料の登録・閲覧RPCとprivate PDF保存先を接続した。PDF登録は未検証資料の保存であり、給与計算へ自動採用しない。

公式料率自動取得、所得税PDFの公式確認/計算規則検証、介護保険の生年月日判定、個別給与の適用フラグ、計算/確定snapshotへの採用は未完了。画面に残る給与連携・自動取得の準備中表示はこれらを指す。Workの手当/給与編集範囲との競合を照合して別途進める。既存給与を新しい未設定料率で置き換えない。

## 公式資料の閲覧導線

所得税ページに折りたたみ式「国税庁の公式資料」を追加。2026年（令和8年）PDFと年度別関連資料一覧を外部ブラウザで開く。閲覧者や会社PDF未登録/読込失敗時にも利用できる。年度を明示し、開くだけでは登録・検証済み化・給与への採用をしない。リンク先は2026-10-10に国税庁の[資料一覧](https://www.nta.go.jp/publication/pamph/01.htm)と[2026年PDF](https://www.nta.go.jp/publication/pamph/gensen/zeigakuhyo2026/data/all.pdf)を確認。

所得税page/entryの既存15テスト成功、Flutter analyze指摘なし。新しい閲覧導線の実機反映はPR統合後のRelease更新で行う。
