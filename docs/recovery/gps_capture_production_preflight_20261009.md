# GPS・写真契約の本番適用前確認と復旧条件

基準 main `a2499ea`（#794 統合後）。2026-10-09 06:30〜06:36 JSTに本番 metadata を read-only 確認した。登録データ行、写真 object 名、個人情報は取得していない。本書は適用・有効化の実行指示ではない。本番 DDL/DML、履歴修正、削除、rollout ON は未実施。

## 適用済みと未適用

| 対象 | repository | 本番確認 | 判定 |
| --- | --- | --- | --- |
| GPS 勤務日・元出勤 | `20261008124940_gps_shift_work_date_evidence.sql` | history は `20261008134105/gps_shift_work_date_evidence`、work_date/source_clock_in_id あり | version が異なる。repo 番号で再適用しない |
| GPS/写真失敗 v1 | `20261008173515_attendance_capture_failure_contract.sql`（#782） | metadata 7列、private.attendance_capture_rollouts、public.get_attendance_capture_capability(uuid) は不存在 | 本番未適用、UI capability OFF |
| 途中現場写真 | `20261008204012_route_journey_capture_staged.sql`（#794） | private.route_journey_rollouts/captures、public.route_journey_workspace(uuid)、専用 bucket は不存在 | 本番未適用、UI capability OFF |

本番勤務日 trigger `attendance_shift_evidence_guard` は `private.validate_attendance_shift_evidence()` を参照。所有者 postgres、SECURITY INVOKER、空 search_path、pg_get_functiondef の MD5 は `d2c9ce7a703a54b014ab88815c648e03`。これだけで repository 全定義の同一性や新migration全連携を証明した扱いにしない。適用直前に実関数・trigger・ACL の保存と差分確認が必要。既存 `docs/recovery/pre_gps_shift_functions_20261008.json` は GPS勤務日変更前の保存資料であり、現在本番の復旧snapshotとして無条件に使わない。

## #782 の CHECK 前提

本番の2 CHECK は migration が比較する正規化式と一致した。

| CHECK | 本番式 |
| --- | --- |
| attendance_verifications_check | `(verification_mode = 'manual') OR (latitude IS NOT NULL AND longitude IS NOT NULL)` |
| attendance_verifications_check1 | `(verification_mode <> 'location_photo') OR photo_storage_path IS NOT NULL` |

これは確認時点の一致。migration はこの2 CHECK が異なる場合に停止する。適用は全体 transaction とし、guard 停止時に先行 ADD COLUMN/table が残らないことを確認する。既存 mode は manual/location/gps_auto/location_photo、event は clock_in/clock_out。新metadataはNULLのまま既存CHECK相当を維持し、古いNULL値の推測修復・時刻/住所の代入・backfillは行わない。

v1 では取得失敗も location_photo のまま保存し、GPS取得時刻、実撮影時刻（不明はNULL）、カメラ復帰観測時刻を分ける。生GPS・写真path・取得状態・日時・住所・modeは不変。既存勤務日guardのserver管理confirmed_at/work_dateとsource/company/site/route/vehicle契約も維持する。daily_report_id の正当な関連付けだけを許可する。失敗を後から成功へ書き換える契約ではない。

## 依存と OFF 条件

本番 companies/workers/company_members/daily_reports/daily_report_workers/route_assignments/route_stops/storage.objects/storage.buckets の存在を確認したが、必要列・全関数・ACL・RLS全体の適用可能性を確定したものではない。

#782 は既存勤務日guard・会社所属・account_access_allowed を前提とする。#794 は先に #782 の列と capability が必要で、実際の本人 route clock_in、active worker、会社所属、parent work_date、route stop、日報リンクRPCが必要。固定班長や推測勤務を作らない。

両 private rollout は enabled NOT NULL DEFAULT false、migration は有効行を登録しない。#794 workspace は両 gate、location_photo/v1、必要 save/link/report RPC、private bucket を確認する。RPC不在・取得失敗・未知version・gate false はOFF。SQL CI成功やRelease導入成功で本番capabilityがONになったと報告しない。

## 写真保持・削除の未完了

本番 `attendance-evidence` は private、15 MiB limit。既存 UPDATE policy は can_manage_attendance、DELETE policy は管理者権限または本人の未参照orphan条件を許可している。したがって #782 の attendance row 不変guardだけでは、保存済み写真objectの置換/削除防止を保証できない。既存policyを本作業で変更していない。

#794 の `attendance-route-evidence` は別private bucketとして作成され、既存attendance orphan削除から分離し、UPDATE/DELETE policyを追加しない。SELECTには会社所属と既存account guardが必要。本人/限定勤怠権限、実際のopen sourceに限定する。ただしservice側の保持、会社/worker/source削除cascadeと写真の扱い、アカウント削除archive、放置uploadの安全な照合回収は未完了。bucket作成だけを保持/削除対応完成として扱わない。

送信結果不明時は登録済みの可能性がある写真を削除しない。固定UUIDと全payloadを保持し、そのUUIDの照会失敗時は別INSERT・別出勤へ推測結合しない。既存登録写真と放置写真を識別できる復旧/保持方針が確定するまでは両gate OFFを維持する。

## 適用前・停止・復旧

1. 適用直前のmain/CI/migration履歴、CHECK、実関数/trigger/所有者/ACL/RLS、bucketと関連削除archive契約を再確認。履歴version差は名前だけで埋めず、実定義と対応を照合する。
2. 現本番の定義と必要データ/写真の復旧snapshotを安全な保管先へ保存し、復元手順を検証する。ユーザーdataや接続情報をIssue/logへ出力しない。現在そのsnapshotの取得と復旧演習は未実施。
3. 隔離環境で既存schema/勤務日実定義へ #782 → #794 を全体transactionで適用し、既存NULL互換、両OFF、失敗/実時刻/住所、翌日固定UUID照会、勤務日/日報リンク、storage保持と削除競合を検証。CI fixture と本番全chainの検証は別物。
4. CHECK前提差、依存欠落、保持/削除未確定、既存データ影響不明があれば停止する。OFFでschema適用するかも別判断とし、自動適用しない。
5. 適用途中の失敗は全体transaction rollbackで新列/table/RPC/policyが残らないことを確認。旧GPS勤務日migration再実行や履歴の書換えを復旧手段にしない。
6. 適用後に問題があれば、まず新規取得をOFFへ戻し、固定draftの照会と既存日報読取を保つ。既にv1 failure行がある場合、旧CHECKをそのまま戻すとNULL写真/GPSの正当な失敗記録と矛盾する。列/table/bucket/原記録をdropせず、保持したsnapshotと差分を見て前進修正を判断する。
7. raw行DDL復旧とstorage object復旧は別。保持済み写真・日報リンク・台帳・承認履歴・後続の正当な勤務をまとめて巻き戻さない。安全な復旧ができることを確認してから有効化を別判断する。

## 状態

完了: metadata読取、CHECK前提一致、GPS履歴version差・新契約未適用・既存bucket保持制約の整理。本番変更なし。

未完了: 本番全chainと実登録データ影響の検証、復旧snapshot/復旧演習、保持/削除archive/放置upload回収、両契約の本番適用/ON、実iPhoneの撮影GPS/offline/複数現場通し確認。以前ログ確認済みのRelease上書き導入・起動成功は別証拠であり、これらの完了を意味しない。今回追加変更のiPhone更新ログは未確認。TestFlightは別途外部待ち/未公開。
