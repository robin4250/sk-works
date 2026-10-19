# 経費明細のID表示と給与反映の確認

基準：remote main `b275e683cc65712f12527d165e429a60fbc90c5c`。
今回の表示変更の親は local `6460688a8c202487142bc8694069997b6d97707f`。
以下は初回調査時点の記録。最新の継続条件は次節を優先する。

## 継続条件の訂正（2026-10-19）

ユーザーは「給与はMac側」という担当分けを撤回済み。給与も継続対象とし、最新main・関連PR・進行中の変更を照合して重複と競合を防ぐ。
注文請書と経費差引の2件だけを最優先にする指定も撤回済み。

- NULL勤務区分による給与計算の欠落は、既存修正をユーザー承認範囲の関数1件へ適用済み。保存済み給与の再計算は未実施。
- 打刻がある一方で給与用勤務行がない日は、打刻から作業量を推定せず、既存の勤務確認へ接続する。出勤3日・給与2日の実データ修復完了とは扱わない。
- 調査対象では税・保険の個別条件が未登録で、計算メタデータも存在しなかった。加入条件・算定基礎・修正額を架空の保険料で補わない。
- 名前付き保険控除のPDF分類修正はPR #1249で統合済み。保険額の自動生成や当該給与の修復とは別に扱う。
- 経費のv2 readerへの画面接続はPR #1252で統合済み。本番capability導入・gate有効化・旧下書き変換・実帳票の差引修復は未完了。

本節は既存成果と未完了の区別であり、新たな本番変更を実行する指示ではない。個別の検証根拠はIssue #273の追記と各PRを参照する。

## 経費申請明細の表示

`ExpenseDetailPdf.append` の日付欄から内部の申請IDを除き、見出しを「日付」にする。
IDの折返しだけで生じていた続き行もなくなる。日付欄自体は残す。
長い内容による正当な続き行は保持する。保存ID・履歴・紐付け・選択条件・金額は変更しない。
この共通部品は給与明細・請求書・支払証明書の別紙で使用される。

## 保険控除：当該データの原因は未確定

PDFは保険項目を一律に削除していない。`payroll_pdf_service.dart` は保存済みdetailの
健康保険料等と `tax_calculation.premiums` を参照し、ゼロ相当の金額は表示しない。
表示だけの欠落か、保存総控除にも含まれないかを同一worker・company・給与月で区別する必要がある。
架空の保険額をPDFへ追加しない。

継続する確認経路：

1. `PayrollTaxConditionsPage._save` → `save_worker_payroll_tax_conditions` →
   `payroll_tax_private.save_conditions`。保存条件の適用開始月と対象社員・会社を確認する。
2. 保存条件の `insurance_mode`、加入フラグ（health/nursing/pension/employment）、
   算定基礎、除外額、`deduction_overrides` と対応する料率月を照合する。
3. `private.refresh_automatic_payroll_internal` → `payroll_tax_private.calculate` →
   statement trigger の実配備版と再計算結果を確認する。条件未登録、legacy設定のゼロ、
   加入フラグOFF、明示的なゼロ上書きは区別する。料率不足のblockedも成功扱いしない。
4. statementのworkflow/revision、総控除、detailの各保険キーと
   `tax_calculation` のblocked/conditions/premiumsを比較し、
   `payrollStatementFromRow` → PDFまで同じ版・金額を保持するか確認する。
5. 確定済み帳票・保存snapshotは再計算で上書きしない。

初回調査時は保存条件・実稼働RPC・当該statementを未照会だった。上の継続結果を含めても、保険不足の全原因確定・当該給与の修復完了とはしない。

## 経費給与精算：既存ソースに未接続の工程あり

`payroll_pdf_service.dart` は別途読取した経費を `ExpenseDetailPdf.append` へ渡す。
この明細表示はgross/net/deductionsを更新しない。
既存の `expense_review_flow_20261013.md` と `expense_cost_connection_20261012.md` も、
給与のconsumer接続を別工程として記録していた。旧担当指定は上の訂正を優先する。
承認済み明細があること、負担先が自社であることだけでは給与精算の根拠にならない。
報告対象の申請で「給与精算」が選択済みかは未確認。

給与精算の接続条件：

- 既存 `expense_settlement_choices` の現在revision・現在の承認と `method=payroll` を参照する。
- 精算対象は既存契約の申請JST月を用い、原額請求の利用月や費用負担先と混同しない。
- 現金精算・支払済み・立替精算・未設定・却下・取り下げ・旧revision・二重精算を除外する。
- 既存のfreeze・receipt・consumptionと確定済みsnapshotを保持する。
- 消費済みの申請を再度加算しない。税・保険の算定対象へ無条件に混ぜない。

本書の旧担当分けを理由に給与作業を対象外にしない。本番適用範囲は実施ごとの承認と検証条件を照合する。
当該給与の正しい控除・精算・振込額、Release実機反映は未確認のまま残す。
