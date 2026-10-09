# 給与保存snapshotの読取・出力接続（限定stage）

#857 exact 139b3da 起点の子Draft。DB/migration/RLSは変更しない。本番未適用・実機未検証。

## 読取入口
本人一覧/本人履歴は my_payroll_statement_rows_with_adjustments、管理一覧/管理履歴は payroll_review_workspace。
#853 scope source 560–603 は保存snapshotの名称・金額・期間・発行・版・状態を返す。
PDF/共有/印刷は PayrollStatementPreviewPage の同じ PayrollStatementRecord を使用し、PayrollPdfService は現行会社/社員設定を取得しない。
通知は閲覧できる期間だけを解決して既存管理一覧へ進む。給与内容の別取得入口ではない。

## 未完了だった接続
初回/再読取待ち・失敗でも一覧由来の古いdraftをPDF出力できたため、読取中/失敗時はpreviewを作らず共有・印刷を停止する。
fresh frozen rowは現在の月確認RPCを呼ばず、その名称・金額・detailを直接利用する。draftのみ現在の確認情報を取得する。
管理認可拒否/名前を特定した未導入workspace RPCの場合だけ本人RPCを再取得する。対象がない・通信失敗を古いRecordで代替しない。
旧DBの名前を特定した未導入確認statusはfresh draft sourceを保持する。

## 統合条件
main c409e0c はsnapshot migration/関連scope/個別確定UIをまだ含まないため、本子差分だけでは保存snapshot sourceは導入されない。
#850/#853/#857 のsource依存を最終mainに安全統合し、SQL応答契約を維持する必要がある。本番導入・実JWT・実機・全月一括確定は未完了。
