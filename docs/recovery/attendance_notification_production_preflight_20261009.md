# 勤怠・車両・通知の本番導入前チェック

基準ソース: main `a086828bb46819d74ca1bf9bd245e8f94a90dbdf`。
2026-10-09 JSTにIssue #273本文と最新コメント（有給適用19:05:57 JSTまで）、#786本文を再読したrepo-onlyレビュー。本資料は本番DDL/DML・gate ON・実機操作を実施した記録ではない。

## 依存を重複させない適用順

まず本番ledgerの番号だけでなく、対象関数本文、引数、ACL、table/trigger実定義を照合する。既存適用済み契約をファイル名の違いだけで未適用と判定しない。以下は未適用だった場合の依存順であり、一括実行用スクリプトではない。

| 順序 | main内のmigration | 必要な判断 |
| --- | --- | --- |
| 前提 | `20261008042058_fix_managed_attendance_overnight_chronology.sql` | 既存管理修正契約を実定義で確認。再適用しない |
| 前提 | `20261008124940_gps_shift_work_date_evidence.sql` | work_date/source_clock_in_id、immutable chronology、管理修正/GPSの実定義確認。gate無しの挙動変更として単独判断 |
| 1 | `20261008153425_vehicle_active_driver_claims.sql` | usage rollout空/default false、旧未退勤claimの推測移行なし |
| 2 | `20261008154241_group_proxy_checkout_staged.sql` | group rollout空/default false、proxy origin guardは常時作用 |
| 3 | `20261008154433_vehicle_meter_snapshots.sql` | claim依存、既存vehicle usage RPCのrename/委譲元実定義を保存 |
| 4 | `20261008160834_attendance_rollout_capabilities.sql` | 読取のみ、完全なRPC/台帳集合が無ければOFF |
| 5 | `20261008161708_group_report_source_attachment.sql` | group checkout依存、完全なsource集合/日報保存検証 |
| 6 | `20261008162618_attach_vehicle_meter_to_report.sql` | claim/meterと日報draft RPC依存、署名前のsnapshot復元guard |
| 7 | `20261008171216_source_member_notifications.sql` | notification rollout空/default false、独立重複防止台帳 |
| 別担当 | `20261008173515_attendance_capture_failure_contract.sql` | GPS capture担当が前提CHECK/実データを確認。本資料では編集/適用しない |
| 通知追補1 | `20261008201729_vehicle_notification_settings_read.sql` | getter、候補/選択UI契約。通知base依存 |
| 通知追補2 | `20261008204054_source_notification_active_recipients.sql` | 停止workerを候補/setter/発行/導線から除外、選択保持 |
| 通知追補3 | `20261008211227_source_notification_restricted_recipients.sql` | 既存削除制限tableの厳密な列/owner/RLS/ACL契約を確認してから適用。共通Auth/RLS変更なし |

#786は#764が#761を含むことを踏まえて7本を一意統合済み。#768は実PostgreSQL fixtureであり追加deployable migrationではない。原本hashと実PG fixture完全一致は `tool/fixtures/staged_attendance_union_manifest.json` と `tool/verify_staged_attendance_union.mjs` を確認する。

## OFF導入とON判断は分ける

OFFでも新trigger/constraint、chronology不変、READ COMMITTED限定、company lock取得、署名入口guard等が登録される。「全機能OFFだから既存操作への影響ゼロ」とは扱わない。未退勤車両、NULL履歴、退勤source、管理修正/削除、月跨ぎ、日報再保存/署名の本番契約を適用前に確認する。旧NULL時刻や対応退勤を推測バックフィルしない。

usage/group/source notification gateは独立。SQL配置を理由にONにしない。active claimがある間のusage OFF/削除は拒否されるため、OFF復帰を即時rollback手段と扱わない。候補照会・proxy退勤・添付・meter・通知を実機で確認してから、対象会社単位で別判断する。

#786 head `09739c7602300fb82568a9b95212a5dd327fd2f9` の12 workflow成功はPR本文記録。現在mainのunion再検証と新通知追補suiteの結果を別確認する。隔離PGlite/PG16競合成功は本番PG17・全既存データ・全ON組合せの完了ではない。

## 有給・角印導入後の保護

最新Issue記録では角印ledger `20261009044454` と有給ledger `20261009100557` は適用済み。勤怠unionは給与refresh/角印生成関数を直接置換しないが、勤怠/日報書込みに既存給与同期triggerが作用する可能性がある。OFF fixtureだけで新有給/角印との全操作共存を証明したとは扱わない。

適用直前の復旧snapshotには対象勤怠・日報・車両・通知/独立台帳・関連FK/trigger/ACL/RLS/関数と、現在の有給/角印関数および保存給与/請求/支払帳票を含める。個人情報/金額は公開repo/CIへ出さない。適用前後で既存帳票全row/印影を保持し、給与scheduler/refreshを手動実行しない。新guardが古い管理修正や会社/worker削除を停止させないことを隔離で再検証する。

## 通知・保持/削除の未完了を混同しない

mainには明示登録後の発行接続、固定日報IDのみ再送、再起動後の保存、車両受信者1〜3名UI、停止/削除制限recipient helperが存在する。古いunion資料の「未実装」は当時の履歴。本番配置/実機通し完了とは別。

app_notificationsの削除はreceipt.notification_idをNULLにするだけで重複防止台帳を保持する。台帳のcompany/source/recipient UUIDには同じcascade FKを付けていないため、会社/worker/アカウント削除で何を保持・匿名化・削除するかは既存削除manifestとの明示照合が必要。既存183 archive試験は今回の新table全対応の証拠ではない。物理通知削除後再発行0、削除済み対象拒否、停止/削除受信者skipと選択/receipt保持を別検証する。

外部メールOAuth/送信基盤・実送信、整備通知間隔、実iPhone通知操作、TestFlightは未完成/未確認を維持する。確認・承認と通知既読を同一扱いしない。権限委任はユーザーごとの限定権限であり、sub-admin一律全許可やMaster機能ON/OFFを会社権限として流用しない。
