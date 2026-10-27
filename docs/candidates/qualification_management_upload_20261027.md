# 管理者の新規資格写真：隔離候補

基盤はPR #1497 privacy-v2の固定SHA `69104f4c67ab89646dc27951cc5f049c837b7c94`。本人写真申請・既存Auth・Storage policy・製品コードは変更しない。新schema `qualification_upload_candidate` の全テーブル・関数はNO GRANT。公開RPC・クライアントアップロード許可・本番配備はない。

`prepare(company,target,request,expectedFullSnapshot,selection)`のselectionは`{existing_path}`または`{mime,bytes,sha256}`。選択SHAはファイルの意図を固定する値で、安全性の証明には使わない。会社・管理者・元の有効セッション・資格全snapshotを照合し、固定IDと予測困難なslot/pathを発行する。端末には不透明IDだけを残し、本文はサーバー15分のprepared状態に置く。

信頼済み検査サービスは`inspection_slot(request,slot,verifiedActor,verifiedSession)`でDBからscopeとobject ID/versionを取得する。Node検査はsession・manifestを固定し、trusted immutable readerから実bytesを取得する。既存`createDocumentFileValidator({sharp,pdfjs})`を`validateFile`として注入する。worker-documents専用identityやbucketへ偽装して流用しない。Magic/MIME/容量・全bytes parser・実SHA・reader原本と固定identityを再確認する。

`record_receipt`は信頼済みDB adapter専用。管理者本人・一般社員・service_roleにはEXECUTEを与えない。会社/actor/session/worker/master/資格/request/slot/path/object ID/version/SHA/MIME/容量を結合し、receiptのUPDATE/DELETEを拒否する。

同じ管理者が`apply(request)`で直接反映する。独立承認は追加しない。元session・現在の権限・全snapshot・全receipt・現在のobject versionをロック下で再照合し、既存の正式/写真履歴triggerと`private.qualification_management_operations`（photos）、`private.qualification_management_result`を使って同一トランザクションで一度だけ保存する。古い写真ファイルは削除しない。

`cancel(company,target,request)`は本文をNULLにする。欠落IDには取消tombstoneを作り、遅れて届くprepareで復活させない。適用済みを取消扱いにはしない。期限も本文NULL、cleanupはSKIP LOCKED/1000件。Cronは最新terminalがfailedなら過去の成功が直近でも新規処理を拒否する。

Nodeテストはparser・DB・readerをmockした契約境界試験。実Sharp/pdfjsの本番稼働確認ではない。PGlite/Native PostgreSQL17は合成Auth・Storage・Cron metadataを使い、実GoTrueや実Cron workerは実行しない。

未完成：実GoTrue endpoint、権限付きDB adapter、実Storage immutable versionの保証、CPU/メモリ/時間制限付きparserの配備、全restrictive/permissive policyとの併用、本人写真能力の回帰、実Cron、孤立ファイルcleanupと保存期限、導入/復旧ガード、マスター制御、実機UI。これらが満たされるまで新規写真・差し替えを利用可能と表示しない。
