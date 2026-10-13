# 車両利用claimの段階導入

基準 main `a2a0ad26cebfbcc39ec99fe49f8b78d4ceb6c202`。本migrationは本番未適用。メーター・日報編集RPC・通知・メール送信はこの変更の対象外。

## 初期状態

`private.vehicle_usage_rollout`は空で、全会社OFF。旧データを推測してclaimへ移さない。通常READ COMMITTEDの既存出勤INSERTやGPS自動出勤、trusted NULL-auth OFFの既存挙動を維持する。車両証拠INSERTの会社／worker／vehicle整合と認証済み本人の現在所属・account guardを確認し、会社単位の直列化lockを追加する。

ON中は出勤INSERTと同じトランザクション内でclaimを作成する。partial unique indexにより一台にactive driverは一人。既存GPS自動出勤RPCにも同じtriggerが作用する。失敗すると出勤INSERT・GPS処理全体もロールバックする。

## 有効化の条件

会社の未退勤車両勤務を、本人確認のうえ既存の正常な退勤処理で終了させる。有効化guardは、明示的な退勤sourceがない旧車両出勤を検知して拒否する。古いNULLや別の退勤から対応関係を推測しない。

車両証拠INSERTはFK取得前のBEFORE triggerで
`pg_advisory_xact_lock(hashtextextended('vehicle-rollout:'||company_id::text,0))`
を取得し、OFF中もcommitまで保持する。rollout変更も同じlockを取得し、待機後のfresh snapshotで未対応出勤を再検証する。rollout行のFOR SHAREは使わない。これによりtoggleのrow lock→company lockと出勤／meterのcompany lock→rollout row lockによる逆順を避ける。

fresh snapshotを保証するためvehicle INSERT・rollout変更・meter RPCはREAD COMMITTED限定とし、REPEATABLE READ等を明示拒否する。会社gate ID変更も拒否する。実二接続の両順序試験成功前に競合解決済みとは報告しない。

車両選択UI・出勤エラーの再選択誘導、代理退勤と管理者修正の互換性を確認してからONにする。**このPR単体で有効化しない**。

## 権限と終了

- 車両の新規claimは本人workerに限定。同一会社の管理者でも他人を運転手として出勤させない。
- 本人または既存の`can_manage_attendance`権限者による明示source付き退勤でrelease。#765のprivate scoped writerによるteam_proxyの場合だけ、immutable origin guard・actor・same company/site/work_dateの実参加者・group gateを追加検証する。一般clientの代理INSERTを許可せず、運転手／meter権限も付与しない。group側lock順の互換性と実二接続組合せを追加検証するまで有効化不可。
- release時刻は退勤の実時刻。work_dateは対応出勤の勤務日。夜勤・月跨ぎで勤務日を変えない。
- claimは本人または既存勤怠管理者だけSELECT可能。account access guardを追加し、直接INSERT/UPDATE/DELETEは認証ユーザーへ許可しない。
- active claimが残る間はrollout無効化・削除を拒否。終了後にOFFへ戻せる。
- 既存の管理者修正による出勤削除ではclaimもCASCADE。worker/vehicle/companyの削除も既存FK操作に従いclaimを削除する。これは勤怠・給与の削除を新たに許可するものではない。旧日報と金融記録はこのmigrationで変更しない。

## 検証

CLI生成migration: `20261008153425_vehicle_active_driver_claims.sql`。

ローカルPGliteに実GPS勤務日migrationと、既存の実public GPS wrapper/ACLをロードしたうえで検証成功。

- OFF維持、旧未退勤がある場合のON拒否。
- 本人INSERTからclaim作成・server work_date維持。
- 非運転手・別会社へのclaim非公開、blocked account非公開。
- 同一車両の二人目のINSERTをunique制約で拒否し、勤怠行も残らない。
- 管理者による他人の車両出勤を拒否。既存勤怠管理者の明示退勤は許可。
- 月末夜勤の翌朝退勤でclaimをrelease、次運転手が利用可能。
- 重複退勤拒否、inactive車両拒否、直接claim編集・rollout読取拒否。
- 実GPS自動出勤RPCがclaimを作り、二人目のGPS出勤を原子的に拒否。

PGliteは単一接続のため、実Postgresの二接続同時競合試験は未実施。排他のDB制約とトランザクション内rollbackを検証したが、実機／本番／全管理者修正シナリオの完了を意味しない。
