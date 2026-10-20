# 管理者資格写真：sqflite connection候補

基準34ae7d43481b9c55878408cd284075aef599d6e6。新connection/path helper/test/docのみ。依存pin/lock、既factory/core/workflow、製品routeと認証はroot所有で変更しない。sqflite2.4.4+2を使うnative adapter候補であり、実機確認済みとは扱わない。

## connection所有

`openDatabase(path, singleInstance:false)`でnative connectionの暗黙共有を防ぐ。既factoryが渡すcanonical private root＋固定DB名だけを受理する。rootのrealpath一致、DB/-wal/-shm/-journalの非symlink・通常fileをopen前後で照合。実app bootstrapがpath_provider由来の同一rootを全isolateへ供給する責任は残る。チェックはsandbox内のconfinementであり、悪意ある並行filesystem writerに対するO_NOFOLLOW atomic openの保証ではない。

全connection操作をFIFO exclusive queueへ通す。再入は現在のactive lease tokenと一致するzoneだけ許可し、callback終了でleaseを失効する。終了後にzoneを継承した遅延Futureはqueue迂回できず拒否する。transaction中のouter Databaseアクセスとnested transactionも拒否し、sqflite deadlockを避ける。

`Database.transaction(exclusive:true)`を所有者とし、callbackにはTransaction専用wrapperだけを渡す。wrapperはcallbackのfinallyで即失効し、COMMIT ACK待機中にも使用できない。core/adapterからBEGINをraw転送しない。DMLはrawUpdateでaffected rowsを返し、PRAGMA queryはrawQuery、非DML executeはexecuteを使う。pluginのtransaction Future成功完了後、既coreがconnection上でcommit後readbackを行う。

begin/callback/commitの失敗・結果不明はconnection全体を同期invalidateし、全users/queued SQLを拒否する。実closeはactive transactionを含むqueue完了後。close Futureはclosedとして観測可能。再利用ではなく新connectionで既固定requestの復旧を行う。

公式契約参照:
- https://pub.dev/packages/sqflite#transaction
- https://github.com/tekartik/sqflite/blob/master/sqflite_common/lib/src/constant.dart （mockchannelのopen/query/update/execute/transactionId項目の参考。採用releaseに対する実行確認はCIが必要）

## 検証状態

純粋Dart filesystem verifier8 assertions成功。fixture専用tmpで固定名・rootalias・sidecar symlink/directory拒否を確認。Dart format/diffcheck済み。

新Flutter methodchannel test8ケースは保存済み・未実行。open singleInstance:false、txnId付きDML affectedRows、core CASの1/0とreadback、callback終了後/commitACK待機中executor拒否、FIFO後close、unknown COMMIT失効、outerDatabase拒否、終了済zone lease拒否、manualBEGIN拒否、path拒否を対象とする。テストケース内の複数assertionがあるため列挙項目数とケース数は同じではない。channel fixtureのCAS状態はmockであり、実SQLiteの原子性・durability・kill検証の代用にはしない。

ローカルFlutter/SDK型解析は実行不可のため未実行。root CIで実lock/採用versionのanalyze＋対象testが必要。過去のpure425/実SQLite47/factory38を今回再実行していない。

実機で残るもの: plugin/OSのcommit完了と再起動readback、複数isolate/engine同一path、kill/端末ロック/容量不足、DB/WALファイル保護とbackup設定、会社actor/session/token pin、元targetへの復帰UI、正規承認経路。製品route・本番・Storage/Auth変更・外部送信は行わない。

## Linuxhost channel registration補修

初回専用CIは型解析・pure/privatepath・factory・実SQLiteまで成功し、channel testsはLinuxhostの未登録databaseFactoryで失敗した。fixtureはpublic `package:sqflite/sqflite.dart` の `SqflitePlugin.registerWith()` を明示する。これは未設定時にnative methodchannel factoryを登録するpublic APIであり、private implementation importや製品factory変更、FFIへの置換、追加依存は使わない。

公式export/registration source: https://github.com/tekartik/sqflite/blob/master/sqflite/lib/sqflite.dart と https://github.com/tekartik/sqflite/blob/master/sqflite/lib/src/sqflite_plugin.dart 。補修後のchannel実行・型解析はroot CI待ち、ローカルFlutter未実行。
