# 本人免許証upload403：mainと本番停止契約の照合

基準main `a086828bb46819d74ca1bf9bd245e8f94a90dbdf`。repo-only調査。DB接続・RLS変更・Storage操作を実施していない。rootの19:40 JST Issue #273記録では、本番storage.objectsに `initial_beta_official_documents_insert_pause/update_pause`（RESTRICTIVE）と本人draft向け `document_submission_upload/private.document_submission_access` が存在する。policy/function名だけでは、正式な提出・承認・保存までの契約が完成しているとは判断しない。

## 実main経路

`lib/features/people/own_document_registration_page.dart` の「登録」は、写真選択前に `updateOwnStatus` と再読込を実行する。添付を選択した場合、その後カメラ/写真選択から `uploadOwnAttachment` を呼ぶ。

`lib/features/people/worker_document_repository.dart` の `updateOwnStatus` は正式テーブルworker_document_statusesへsubmitted、original_verified=false、期限/notesを直接INSERTまたはUPDATEする。`uploadOwnAttachment` はcompany/worker/requirement/status/新object名のpathでworker-documentsへupsert:falseの直接Storage INSERT、その後正式status attachment_path更新、旧object削除へ進む。添付upload失敗前にも正式statusだけ変更される可能性があり、UIの失敗表示は全操作rollbackを意味しない。写真選択キャンセルでも先行status保存は残る。

本番RESTRICTIVE INSERT拒否なら、別の許可policyを追加してもその拒否を打ち消せない。upsert変更や管理者権限追加は解決契約にならない。upload403自体の時点では新object登録成功を確認しておらず、旧object削除分岐にも未到達。

## 調査範囲と未発見

mainおよびローカルworktreeのSQL/Markdown/Dart、git全参照履歴の関連commit名、OpenPR、GitHubの関連issue/PR検索では停止policy/提出draft契約の実装元を発見していない。したがって停止を意図しない残骸とは判断しない。過去本番ledger/実定義・実行記録を本番担当が確認する必要がある。

既存 `docs/recovery/account_deletion_source_20261008/account-deletion/policy.mjs` には、会社正式書類保管庫というoperator decisionと `officialDocumentRetentionFinalized:false` があり、worker-documentsを削除保持未確定の対象に含める。ただしこれはupload停止導入理由の直接証拠ではなく、両者を混同しない。

## 最小修正候補

1. 本番担当が停止導入ledger/sourceと本人draftの実schema・path・RPC・ACL/RLS・提出/承認/promotion・削除/保存契約をexportしてrepositoryとの差分を照合する。既存正式行・添付・履歴の保持を確認する。
2. 既存本人draft経路が完成していれば、本人画面をその既存契約へ接続する。先に正式submittedを保存せず、本人draft作成→そのdraftに許されたpathへ添付→明示提出と再照会の成功確認へ進む。本人/会社/requirementをserverで検証し、他人・他社・approved/frozen draftのuploadを拒否する。承認後の正式反映は既存server契約に限定する。
3. 通信不明では正式行や旧objectを削除せず、固定draft/submission IDから状態照会する。upload成功後の提出失敗は「下書き保存/提出未確認」と区別する。取消や選択キャンセルを登録成功として扱わない。
4. 契約が未完成なら、正式書類への直接書込停止を解除せず、本人画面の未対応操作を正確に案内し既存読取を残す。一律機能停止/通常閲覧不可にはしない。これは403根本修正や実upload成功とは別。

product候補は本人repository/本人書類画面/「？」ヘルプとその回帰テスト。共通Auth、Master、会社権限、正式Storage policy、他人の書類管理を広げない。正式statusや添付の過去保存内容を推測修復しない。

## 必要な検証

本人draftのみupload可、他社/別worker/path偽装/承認済み拒否、停止中official upload拒否維持、写真選択キャンセル時の正式status不変、403/通信不明/提出失敗/再起動再照会、差し替え時の旧正式object保持、明示提出成功と承認後反映、期限/notesだけの場合の正当な保存を確認する。既存読取と会社限定管理導線も保持する。

今回完了はsource所在・部分保存可能性・契約不一致・最小修正範囲の調査のみ。停止根拠、draft実定義の復元照合、商品修正、CI、最新Release実機upload成功は未完了。
