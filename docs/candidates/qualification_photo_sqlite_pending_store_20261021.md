# 資格写真申請のSQLite PendingStore core候補

基準 `17c3441de67f37582d7c4f469fd01dcd9f5a330b` のtransaction-owner follow-up（元submission基準 `5f610acf`）。製品route、mobile plugin、保存path、認証/RPC adapterは未接続。pubspec/lock、既repository/model/workflowは変更しない。

## 契約

`AdminQualificationSqliteConnection` は同一connectionの全accessを `exclusive` で直列化し、query/execute（affected rows）を提供する。別connection/processの競合はSQLiteが排他する。transaction所有者adapterがbegin/callback/commit失敗時にrollbackを可能な範囲で試み、coreはtransaction Futureの失敗・不明結果でconnection全体をinvalidateする。adapterはqueued/new SQLを拒否し、復旧には新connectionを要する。失敗をfalseや成功へ変換しない。

専用DBにkey PRIMARY KEY/value NOT NULLの1表を作る。初回insertはunique競合のみDO NOTHING。更新/削除はkeyとexpected valueの条件付きSQL。connection.transaction(callback)内の専用executorでSQLを実行し、transaction Futureの成功完了後にconnectionからreadbackし、一致した場合だけtrue。coreからBEGIN/COMMIT/ROLLBACKを発行しない。affected rows 0のみfalse。不明commit・IO・busy・readback不一致はthrow。null→nullは所有権を得ないため拒否する。

WAL・synchronous FULL・read_uncommitted OFFを初期化し、各操作前に実値を検証。設定が通ったというAPI応答だけで推定しない。SQLite公式はconnection/process間のwriter直列化とWAL+FULLのcommit同期を説明する:

- https://sqlite.org/isolation.html
- https://sqlite.org/pragma.html#pragma_synchronous
- https://sqlite.org/lang_transaction.html

既repositoryは保存文字列の完全一致readbackを要求する。そのためコマンド文字列の順序を勝手に変えず、SQLite値には `{"command_json": "原文", "version": 1}` のcanonical JSON envelopeを保存する。envelopeのキーは決定順序、原文はJSON objectとして検証し、readは原文をそのまま返す。配列順序・固定request・revisionも保持する。コマンドのscope/schemaは既repositoryの厳密parserが引き続き担当する。

## 実DB検証

`tool/verify_qualification_photo_sqlite_store.dart` → Python stdlib `sqlite3` subprocess fixture。DB pathは作成した `/tmp/sko-qualification-sqlite-*/pending.sqlite3` のみに制限し、終了時に削除する。本番・実appデータ・ネットワーク不使用。

45 assertions成功（テストケース数ではない）:

- 別process/connectionの同時insert/update/deleteで勝者がそれぞれ1件。
- 同一connectionの別Storeもtransactionが交錯しない。
- canonical envelopeと原文/配列順序保持、外国namespace・非object拒否。
- commit応答消失はthrow、別process読取りでcommit保持。
- 実subprocessのCOMMIT直前 `os._exit` はrollback、直後はcommit保持。新processのreadbackで確認。
- commit/readback間の別connection書換えは成功とせずthrowし、競合データを上書きしない。
- 実SQLite writer競合（SQLITE_BUSY）、弱めたFULL/isolation、不正envelopeを拒否。
- BEGINがSQLiteで成功した後の応答消失もtransaction失敗としてrollback/connection失効を通す。元errorを保持し、待機中の別Store読取/更新・旧connectionの新Storeは拒否。新connectionで元記録の再読込とCAS復旧を確認。
- transaction callback内のouter connection使用と、callback外へ持ち出したtransaction executorの使用をfixtureで拒否。commit後のackをgateし、callback戻り値だけではStoreが成功せず、transaction Future完了とreadback後に成功することを確認。
- 不明transaction後は同じStoreおよび同じconnectionを使う新Storeも拒否。

既submissionの純粋fixture425 assertionsも成功。Dart formatとdiffcheck済み。Flutter解析/testは未実行。

## 未接続・残条件

mobile plugin依存は追加していない。最小sqflite adapter案は、`connection.transaction`を`database.transaction((txn) => operation(TransactionExecutor(txn)))`へ対応させる。callback内はtxnだけを使用しouter Databaseへ戻らない。SQLのBEGIN/COMMITをraw転送しない。exclusiveはconnection全accessとcommit後readbackを含む。invalidateは同期的にrevokedを立て、queued/new SQLを拒否し、closeは安全に後続処理する。新connectionでのみ復旧する。

sqflite公式のtransaction契約: https://pub.dev/packages/sqflite#transaction 。この対応は設計候補であり、実plugin adapterの実装・依存採用・mobileでの実証ではない。affected rows取得とcommit応答/例外契約は採用versionで確認する。Python fixture内部の明示BEGIN/COMMITは実DB検証bridgeのtransaction所有者だけが実行し、製品adapterの実装を意味しない。

実adapterは同一のprivate絶対path、connection全体exclusive/invalidate、plugin commit完了の意味、全connectionのPRAGMA読戻しを証明する必要がある。sqflite等のversion/SDK/platform適合は別工程。iPhoneで複数repo/isolate/engine、アプリ強制終了/再起動、端末ロック、容量不足、実DB/WAL配置、実RPC前後・ack前後を確認する。

今回のos._exit検証はプロセス終了境界であり、iPhone実機・OS crash・電源断耐久性の実証ではない。SQLiteの耐久性はOS/VFS/storageのsync契約にも依存する。実mobile adapterや元target復帰UI、本人/会社scope pinを省略しない。削除実機完了・本番導入済みと扱わない。
