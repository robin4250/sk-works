# build 6 実機指摘: 保険料・共通手当の接続確認

基準 `075b4004fffffcf53458ef28ea60a289c565506a`。担当Dの読取調査と隔離fixture追加検証。
本番接続・DDL/DML・有効化・実額登録・給与再計算・配布は行っていない。

## 共通手当: 保存と給与適用は別操作

既存 `company_common_payroll_bridge_20261020.sql.review-only`、`company_common_payroll_effective_20261020.sql.review-only` と publication UI を再利用する。別の価格マスターや新しい計算処理は追加しない。

- 共通設定の保存だけでは既存給与に現在単価を遡及適用しない。「給与への適用月」で給与形態・適用月を選び、保存済み設定をpublicationとして登録する。
- 現行SQLは適用月以上・次の適用開始月未満の同形態の自動下書き全件を既存refresh/syncで再計算する。確定済み・手入力は除外し、同requestはreceiptを返す。
- 新規適用月は現在月以降のみ。過去月の未確定給与への一括訂正はこのAPIでは拒否する。今回の「未確定給与すべて」が過去月も含む場合、現行契約だけで完了とは言えない。過去月訂正の原本保護・承認・対象限定契約が別途必要。
- serverは再計算scope件数を返す。今回の後続client修正で検証済みreceiptの整数件数を表示する（下記）。blocked/除外理由の全件表示はまだ提供していない。未入力hoursはblockedのまま。件数表示を実額反映全件成功の証明としない。
- 旧共通/identity基盤、bridge/effective SQL、会社activation、復旧/互換条件の本番準備が未完。画面があるだけで本番の共通手当連動完成とは扱わない。

## 退勤・勤怠編集による再計算の追加検証

既存effective fixtureに、給与refreshの明示呼出を使わないattendance_entries INSERT/UPDATE検証を追加した。原本fixtureの実attendance_refresh_payroll/attendance_sync_payroll_detail triggerを使う。

合成の月給300,000円・共通月手当3,000円・共通日手当300円をpublicationした上で、同日2現場に各0.5人工をINSERTすると1日分だけ加算され303,300円。片方を0人工にUPDATEしても303,300円、両方を0にすると303,000円へ戻る。unit_resolutionの共通日項目quantityも1→0、差引額も支給−控除と一致。

これは勤怠保存後のDB連動の証拠であり、実iPhoneの退勤ボタン→署名/日報→attendance保存までのE2E、実本番trigger配備、実従業員金額を証明しない。既存の不足日の原本補完も行っていない。

## 保険料

既存manual候補と実給与fixtureを再検証し、本人負担月額を明示した保存/CAS/audit、空欄と明示0の区別、既存率/固定方式保持、税・住民税・共通手当への合流、明細named totals、確定保護が成功。既存の税条件画面はsave_worker_payroll_tax_conditionsへ適用開始月・本人条件を保存し、対象未確定給与再計算へ接続する。

今回実機の同一本人・対象月・条件version・statement revision・本番関数は未照合で、実額未反映の原因を今回のローカル成功だけでは断定しない。本人加入条件・月額を推測で作成せず、正しい資料と保存済み原本から確認する。

## 実行結果

- `node tool/verify_company_common_payroll_effective.mjs /tmp/sko-validation/node_modules/@electric-sql/pglite/dist/index.js`: 追加勤怠INSERT/UPDATEと既存履歴/次適用月境界/replay/CAS/viewer/確定/末尾rollbackすべてPASS。
- `node tool/verify_payroll_manual_insurance.mjs /tmp/sko-validation/node_modules/@electric-sql/pglite/dist/index.js`: 既存manual統合の全検証PASS。
- PostgreSQL実同時接続、実JWT、Flutter/UI/PDF、実本番、実機は今回未実施。以前のFlutter起動時のmetadata通信拒否は再実行・迂回していない。

## 後続修正: publication完了時の再計算件数

既存 `recalculated_scopes` を、RPCのcompany/request/給与形態/適用月/publication version/timeline version照合を通過した後だけ `applicationSummary` に保持する。一般readは件数を作らない。非負の整数だけ採用し、0は0件、欠落・負数・文字列・小数などは不明として扱う。タイムライン件数・手当項目数から推測しない。

完了Snackbarと適用月パネルに同じ文面で「適用月を登録しました。給与下書きの再計算：N件。未入力の時間数がある給与は計算保留です。」を表示。不明時は「再計算件数を確認できません。」とする。確定/手入力/別適用期間の除外理由をserverが返さないため、数値や理由を創作しない。現在の結果表示であり、本番有効化済み・実額反映全件成功とは扱わない。

純粋Dartの新検証 `tool/verify_common_payroll_publication_summary.dart` がPASS。0/1/12/32bit最大整数、負数/文字列/小数/bool/null/配列/object/欠落・タイムラインからの推測なしを確認。既存SDK/widgetテストに有効件数/不明件数、0と不明、初期表示書込なし、logout後の旧完了表示拒否の回帰を追加したが、Flutter起動禁止のためこれらの新ケースは今回未実行。Dart formatterによる修正sourceの構文読取とdiff-checkを実施。

ヘルプ・翻訳の統合文案: 「保存済み共通手当の適用月を登録すると、対象の自動給与下書きを再計算します。完了時の件数はサーバーが返した再計算件数です。件数を確認できない場合は不明と表示します。未入力の時間数がある給与は計算保留で、確定済み・手入力給与は変更しません。再計算件数だけで全員の実額反映完了とは判断しません。」

結果の表示scope: 新しい適用確認を開始した時、結果照合の開始時、給与形態/月の変更時、再読込開始時は旧完了件数を非表示にする。company/actor切替と背景移行は既存state破棄・generation拒否を保持し、旧遅延応答で新しい完了表示を出さない。再読込はtimelineを取得するだけで、過去receipt件数を推測して復元しない。新月/結果不明で旧件数を現在結果として表示しないwidget回帰を追加（Flutter未実行）。
旧件数Snackbarも所有するcontrollerだけを閉じ、無関係なSnackbarを一括削除しない。actor/会社/背景切替でも旧完了通知を残さない。
