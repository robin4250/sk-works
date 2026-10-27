# 管理者の新規資格写真：隔離候補

基盤はPR #1497 privacy-v2の固定SHA `69104f4c67ab89646dc27951cc5f049c837b7c94`。本人写真申請・既存Auth・Storage policy・製品コードは変更しない。新schema `qualification_upload_candidate` の全テーブル・関数はNO GRANT。公開RPC・クライアントアップロード許可・本番配備はない。

`prepare(company,target,request,expectedFullSnapshot,selection)`のselectionは`{existing_path}`または`{mime,bytes,sha256}`。選択SHAはファイルの意図を固定する値で、安全性の証明には使わない。会社・管理者・元の有効セッション・資格全snapshotを照合し、固定IDと予測困難なslot/pathを発行する。端末には不透明IDだけを残し、本文はサーバー15分のprepared状態に置く。

信頼済み検査サービスは`inspection_slot(request,slot,verifiedActor,verifiedSession)`でDBからscopeとobject ID/versionを取得する。Node検査はsession・manifestを固定し、trusted selected-version readerから実bytesを取得する（恒久的な不変性は主張しない）。既存`createDocumentFileValidator({sharp,pdfjs})`を`validateFile`として注入する。worker-documents専用identityやbucketへ偽装して流用しない。Magic/MIME/容量・全bytes parser・実SHA・reader原本と固定identityを再確認する。

`record_receipt`は信頼済みDB adapter専用。管理者本人・一般社員・service_roleにはEXECUTEを与えない。会社/actor/session/worker/master/資格/request/slot/path/object ID/version/SHA/MIME/容量を結合し、receiptのUPDATE/DELETEを拒否する。

同じ管理者が`apply(request)`で直接反映する。独立承認は追加しない。元session・現在の権限・全snapshot・全receipt・現在のobject versionをロック下で再照合し、既存の正式/写真履歴triggerと`private.qualification_management_operations`（photos）、`private.qualification_management_result`を使って同一トランザクションで一度だけ保存する。古い写真ファイルは削除しない。

`cancel(company,target,request)`は本文をNULLにする。欠落IDには取消tombstoneを作り、遅れて届くprepareで復活させない。適用済みを取消扱いにはしない。期限も本文NULL、cleanupはSKIP LOCKED/1000件。Cronは最新terminalがfailedなら過去の成功が直近でも新規処理を拒否する。

Nodeテストはparser・DB・readerをmockした契約境界試験。実Sharp/pdfjsの本番稼働確認ではない。PGlite/Native PostgreSQL17は合成Auth・Storage・Cron metadataを使い、実GoTrueや実Cron workerは実行しない。

未完成：実GoTrue endpoint、権限付きDB adapter、実Storageの選択版とbytes結合・writer制約の検証、CPU/メモリ/時間制限付きparserの配備、全restrictive/permissive policyとの併用、本人写真能力の回帰、実Cron、孤立ファイルcleanupと保存期限、導入/復旧ガード、マスター制御、実機UI。これらが満たされるまで新規写真・差し替えを利用可能と表示しない。

## HTTP・DB adapter候補（未登録）

`createQualificationInspectionHttpEndpoint` はFetch handlerを返すだけで公開routeを登録しない。POST/HTTPS/登録path・Bearer・application/jsonを要求し、request_id/slot_idのliteral UUID二項目だけを受ける。duplicate/escaped keysや他項目は拒否する。bodyは1024 bytes/256 chunks、読み取り期限を設ける。Body/auth/rate依存だけの期限であり、検査全体の実行時間やparser停止を保証するものではない。応答はno-store、固定error codeのみでtoken・path・DB例外を記録/返却しない。

rateLimiterはhost所有の共有・原子的なbackendを注入する契約。ingress 60件/分と検証済みactor 20件/分を要求し、未構成・障害時はfail closed。trusted contextのclientKeyはhostが実ネットワーク情報から作るHMACであり、bodyやX-Forwarded-For等のheaderから採らない。共有limiter/HMAC鍵/実session verifierの運用配備は未提供。

`createQualificationUploadDbAdapter` はhost所有poolから専用clientを取得し、固定SQL・BEGIN/COMMIT/ROLLBACK、statement 5秒/lock 3秒を設定するコード。proofはallowlistを接続待ち前にコピーする。SQL/credentialsをHTTP入力から受けない。rollback異常はclientを破棄し、COMMIT結果不明は成功にしない。

Nativeはfixture ownerだけで確認する。本番用の最小権限role/grants・TLS/CA・credential・bounded max poolとconnectionTimeoutMillisの設定は未提供。本番superuserやservice_roleを流用してNO GRANTを迂回する配備は禁止。pool取得期限、selected-version reader期限、parser workerのCPU/メモリ/壁時計期限と実プロセス終了はhost側で必要。HTTP全体にPromise.raceを置くだけではunderlying処理を停止できない。実broker/reader/parser/GoTrue/Storage policy/実Cron/実機を完成扱いにしない。

### 選択版readerとの隔離結合

inspectorは `readSelectedVersion` に選択済みbytes数とSHA-256を渡す。旧 `readImmutableVersion` だけの依存は拒否する。readerの固定versionId REST、前後metadataと実SHA検査を通ったbytesだけparser/receiptへ進める。実reader＋実inspectorの合成6試験は成功したが、HTTP/metadata/DB/session/parserは合成依存であり本番接続ではない。Storage APIの実稼働版、最小権限、現在版metadata、parser隔離、writer制約は未達。公開route/Storage許可/NO GRANT/OFFは変更しない。
