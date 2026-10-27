# build24 本人専用PDF保管倉庫候補

## 調査した既存main

2026-10-27 mainの `AttendancePdfService.buildPdf(month, WorkerAttendanceMonth, workerName)` は本人月データを引数で描画する。全員用 `buildWorkersPdf` は倉庫に使わない。

`PayrollPdfService.buildPdf(PayrollStatementRecord)` は既定で `ExpenseDocumentRepository.load` を呼ぶ。本人PDF倉庫ではサーバーが本人だけに絞った固定snapshotを作り、第三者経費・添付・会社内部資料・会社印影などを含めない専用projectionとadapterが必要。現在設定や新会社データから過去給与を再計算しない。

本人取得は既存 `PayrollStatementRepository.loadMyStatements` → `my_payroll_statement_rows_with_adjustments` がある。ただし会社脱退後にも権限が続く保証としては使用できず、所属終了前に本人と元会社が確認できる固定snapshotを保管する必要がある。氏名やクライアント指定worker IDを所有者認証に使わない。SKO IDとauth user/workerの正規対応の確定は所属担当と連携して行う。

## 独立実装

`tool/personal_vault_manifest.mjs` は認証そのものを実装しない。信頼済みサーバーの本人認証・完全な原本一覧から計画を作る純粋関数。

- 同じperson ID、元会社、対象期間の本人出勤表/給与だけを許可。
- 確定・不変snapshotがない行は拒否。月途中は切替日を上限とするsnapshotが必要で、元会社の将来記録を含めない。
- source ID+revision+snapshot hashをキーにし、再試行・再独立でも同じ原本PDFを重複生成しない。新revisionは別版として保全。
- manifest内の同一source重複は拒否。一覧未完・生成失敗・欠落・重複receipt・元snapshot不一致は完了扱いしない。
- 検査済PDF bytesのhashと不変版・本人・元会社の一致があるreceiptのみ受理。

これはPDF本文の漏洩検査、認証、Storage ACL/RLS、DBの原子処理、実際のPDF生成・保存の代替ではない。receiptをクライアント入力から受理してはならない。

## 未接続の本番設計

Master gate `personal_pdf_vault` を既存の全体制御へ追加する担当と契約済み。欠損OFF。開始とcommitでDB内の同じgate lockを再照合する。OFFでも保存済みファイルは消去せず、本人専用の閲覧権限は所属から独立して維持する。

本人限定の非公開immutable object、catalogと出力manifest、短命の本人認証付きダウンロード、PDF表示/端末保存/印刷だけの画面を実装する。会社/管理者/新会社に倉庫閲覧を自動付与しない。PDF原本は編集・差替・削除不可、訂正は新しい版を追加。会社の正式記録は元会社に残す。

所属切替は原本inventoryの完成→全PDF verified receipt commit→切替transactionの順。失敗時は切替を未完として復旧し、PDF成功を偽らない。短命URLの出力やファイル本文を監査ログへ書かない。代表者自身が元会社の労務/給与を閲覧できるかは別認可。

未完: auth/SKO identity対応、実原本projection、実PDF adapter・本文検査、DB catalog/RLS・Storage、Master画面、画面導線、切替transaction、実認証・CI・本番/実機。既定OFFの設計候補であり機能完成ではない。

検証: `node --test test/personal_vault_manifest.test.mjs` 合成3件成功。実データ・署名・資格情報未使用。本番書込み0。ローカルFlutter/Dart0。
