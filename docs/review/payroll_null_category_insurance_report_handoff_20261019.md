# 給与の合計不一致・保険未反映・勤務日数差の引継ぎ

基準main：`bedac66af938989a9e9d314ee2d96cd01b831a01`。
本書は原因と修正候補の記録だけ。給与コード・DB変更はMac側へ一本化する既存ルールを維持し、ここでは実装・SQL実行・migration・再計算・本番変更を行わない。確定済み明細や保存snapshotを更新しない。

## 給与合計と基本給行が異なる直接原因

この記録を依頼したrootは、保存snapshotの社員番号・社員名・対象月による限定SELECTで対象を1件に固定した。氏名、社員番号、UUID、実給与額、会社名、個人条件、実JSONは本書に記載しない。先行した画面額による照合や会社表示名による照合は一致0件だったため、その結果だけでは原因を断定していなかった。

対象draftは総支給0、基本給キーあり、基本給行と総支給が不一致。単価設定は日給で通常日単価が正。給与集計対象の保存済み勤務2件は基本数量が正、給与計算元は従業員設定だが、両方のwork_categoryがNULLだった。

本番catalogのrefresh関数body MD5は、保存済み `20261013175452_payroll_unit_conditions.sql` の `private.refresh_automatic_payroll_internal` と完全一致した。この関数の従業員単価分岐は `category:=a.work_category` とする。NULLに `_daily` 等を連結したキーはNULLとなり、settings参照結果がNULL、coalesceで単価0へ落ちる。基本数量が正でも総支給の勤務分が0になる。

対して保存済み明細内訳の `sync_payroll_attendance_detail` はwork_categoryを `coalesce(work_category,'day')` で正規化するため、同じ勤務を通常日単価で計算して基本給行を非0として保存する。この正規化の不一致が、対象の総支給0・基本給行非0の直接原因である。rootの固定合成JSONによる読取SELECTでも、NULL分類で単価を失い、通常日への正規化では既存内訳と一致することを再現した。合成検査値は本人の給与額を示さない。

PDFの基本給欠落時fallback（`出勤に基づく支給額`）は別の潜在候補として先に見つかっていたが、今回対象は基本給キーが存在する。今回の確定原因と混同して修正範囲を広げない。

## Mac側での最小修正候補

保存済みrefresh関数の単価分岐で、NULL分類を既存内訳と同じ通常日 `day` として扱う最小修正を検討する。既存の給与計算元選択、残業・早出、日給/時給/月給、手当、税・控除、権限、確定保護を変更しない。過去データ全件の分類UPDATEや一括再計算を解決策にしない。

変更前に対象関数の前提hashを再照合し、現行定義・依存関数・trigger順序をバックアップする。隔離環境ではNULL分類と明示day分類が同じ集計となること、既存night/holiday/holiday_nightが変わらないこと、従業員設定以外の計算元や月給等の既存結果が変わらないこと、基本給等の内訳合計と総支給が整合すること、確定済みstatement/snapshotを更新しないことを既存fixtureへ追加して検査する。検査成功と本番適用・対象draft更新・iPhone表示確認は別々に記録する。

この文書は本番変更の承認ではない。既存のバックアップ・復元・承認条件を満たすまで適用しない。

## 保険控除は別原因：条件未登録

対象は税計算結果なし、保険detailキーなし、当該従業員のworker_conditions全versionが0件、従来の固定社会保険額も0だった。したがって今回の保険未反映は、保険額が保存済みなのにPDFだけ消している状態ではなく、計算に必要な本人条件が未登録の状態として区別する。

既存の税計算条件保存と固定控除UIを再利用し、対象月の適用開始、加入条件、標準報酬等の算定基礎、適用料率、明示上書きを正しい資料から登録する必要がある。架空の保険額をPDFや設定へ追加しない。未登録を加入対象外・保険料0とみなさない。NULL分類の修正だけで保険条件が自動登録されるとは説明しない。

## 3日打刻と給与用勤務2件の差

同月の報告対象3日にはそれぞれ出勤・退勤の打刻がある。12日と16日は給与用attendance_entries各1件、基本数量が正、正式署名済み日報・参加者との対応が確認された。13日はattendance_entries0件で、打刻側daily_report_idなし。対象者が作成者または参加者の13日の日報も0件だった。

打刻だけを根拠に給与用原本や署名を自動生成・複製しない。13日分は通常の記録補完・承認手順で原本を確定する必要がある。日報の作成・提出・署名、または既存仕様で許可された承認済み勤務修正のどちらが適切かを区別し、必要な本人操作・承認を経る。その後、既存の参加者・勤務生成経路で給与用勤務が作られたことを確認する。現存2件のNULL分類問題と、13日の原本不足は別工程である。

## 保存済みsourceの再利用

本番catalogが返した関数body MD5とmain migrationのドル引用bodyを読み取り比較したところ、以下4件が完全一致した。新しい関数体系を作らず既存sourceを用いる。

| 関数 | 一致するmigration | body MD5 |
|---|---|---|
| payroll_tax_private.calculate | 20261014033249_payroll_fixed_deduction_overrides.sql | 17ab2de831a2db457b8ad7ae4283b7fc |
| payroll_tax_private.save_conditions | 20261010030208_connect_payroll_tax_calculation.sql | d70b90d9e00ced26bc118a6493e957a3 |
| private.refresh_automatic_payroll_internal | 20261013175452_payroll_unit_conditions.sql | 2c5230eea880fe8cddbe60bc6c4c0782 |
| public.save_worker_payroll_tax_conditions | 20261010030208_connect_payroll_tax_calculation.sql | 882c4849b11231d2a09b6abdc32e56a0 |

先行 `expense_payroll_followup_20261019.md` の「実データ未照会・原因未確定」は当時の記録として保持する。本追補はrootから受領した限定照合結果による到達点を記録する。経費の給与精算consumer未接続、共通手当RPC未導入、保険条件未登録、勤務分類NULL、日報原本不足を一つの原因にまとめない。
