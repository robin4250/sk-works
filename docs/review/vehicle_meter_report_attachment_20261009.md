# 日報への車両メーターsnapshot結合

基準 main `a2a0ad26cebfbcc39ec99fe49f8b78d4ceb6c202`。新migrationのみ。#761/#764の車両claim・event schemaに依存。本番未適用、rollout OFF維持。既存migration・認証・汎用RPC・RLSは変更しない。

## RPC契約

`get_report_vehicle_meter_context(p_report_id uuid)` はJSON配列を返す。各行:

`source_clock_in_id, worker_id, vehicle_id, vehicle_name, work_date, has_claim, has_event, event_id, previous_km, current_km, distance_km, baseline_decreased`。

`attach_vehicle_meter_to_report(p_report_id uuid, p_source_clock_in_id uuid)` はJSON objectを返す。

- 登録済みevent: `attached=true, has_claim=true, has_event=true`、source/event/worker/vehicle/work_date/previous_km/current_km/distance_km。
- claimありevent未保存: `attached=false, has_claim=true, has_event=false`。日報下書きは残せるが、運転手の登録待ちとして署名前に案内する。
- 車両なし、claimなし: `attached=false, has_claim=false, has_event=false`。legacyから推測してclaimを作らない。

複数勤務がある場合は全該当sourceを返す。最新を勝手に選ばず、一つのworker枠へ異なるeventを上書きしない。

## 権限・整合性

呼出者は現在の会社member・active workerで、保存されたreportのcreated_byまたはupdated_byと一致し、実際に同じ会社・現場/ルート・勤務日に出勤し、report rosterにも含まれる必要がある。勤怠管理者でも、その勤務の参加者でなければこの狭いRPCでは許可しない。

日報入力者が運転手でなくても、自分がその勤務の正当な入力者なら他運転手の登録済みsnapshotを取得・結合できる。raw meter eventの広いSELECT権限は与えない。運転手の数値入力権限は増やさない。

source/claim/eventの会社・worker・vehicle・work_dateと、reportの現場/ルート・日付・rosterを照合する。車両現在値を参照して差分を再計算せず、車両現在値も更新しない。署名がある日報へ新規結合は拒否する。既に同じsnapshotが結合された日報の再送は、署名を変えずread-onlyで成功を返す。

## 保存列と再保存

新列は`daily_report_workers.vehicle_meter_event_id`, `vehicle_meter_source_clock_in_id`, `previous_odometer_km`, `trip_distance_km`。既存`odometer_km`には今回の累積メーター値を入れる。`route_assignment_id`は出勤時のrouteを使用する。既存rowsへの推測backfillはしない。

既存`save_daily_report_destination_draft`はworker rowsをDELETEして作り直す。そこでprivateなreport/worker→event/sourceのidentity ledgerを保持し、同じeventの復元だけ許可する。リンク済みreportの会社・日付・現場/ルート変更を拒否し、worker snapshotが失われた状態の署名を拒否する。このguardはリンクのない既存reportには作用しない。

汎用の下書き保存・署名RPCは変更していない。rollout ONかつ保存roster・会社・勤務日・現場/ルートに一致する実claimがある場合は、未退勤・未event・未attach・snapshot不一致をすべての署名列でサーバー拒否する。status、signed_at、本人・代表者・監督者の各署名列のどこからでも同じguardを通る。OFFやclaimのないlegacy情報から未登録車両を推測しない。

## UI接続と検証

journey laneと契約済み。strict capabilityがONの場合だけ旧worker vehicle RPCループをskipし、実日報保存後にcontextを取得してcommitted eventをattach。OFFでは旧処理を維持する。新列のSELECTもschemaがないOFF環境で実行しない。PDFは前回・今回・当日差分を区別する。

ローカルPGlite PASS。実既存の下書きRPC、実meter RPC、実RLSを使用。非運転手の正当な入力者による狭いcontext/attach、raw eventの他運転手非公開、actual draft DELETE/reinsert後の同値復元、lost snapshot署名拒否、承認なしsigned→draft拒否・承認済み編集申請の消費後に元event復元・現在車両距離を巻き戻さないこと、signed retry、fresh signed attachment拒否、pending eventの全署名列拒否・OFF時の既存署名保存維持、roster欠落、別月・別現場・別会社・非参加管理者・blocked account拒否、他event上書き拒否、private/anon ACL、車両現在値不変を確認。

CIはimmutable dependency commit `3662a29171a8a3e947780165a674c4134ea46f37` (#764、実Postgres死活競合に対応したロック順修正を含む)からschemaを読む。このPRへ古い#761/#764 migrationをコピーしない。PGliteは二接続競合試験ではなく、実機/PDF/本番は未検証。管理者の非参加時の承認修正やlegacy履歴のON再編集は別対象。
