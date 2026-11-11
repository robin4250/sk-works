# GPS・写真契約と有給の交差レビュー

2026-10-09、main `a086828bb46819d74ca1bf9bd245e8f94a90dbdf` の repository-only レビュー。DB接続・本番metadata取得・変更は行っていない。朝の `gps_capture_production_preflight_20261009.md` の観測値を現在値として扱わない。有給の適用結果は本番担当の実施記録で別確認する。

## schema適用と業務有効化

`20261008173515_attendance_capture_failure_contract.sql` は7 nullable列、OFF既定のprivate rollout表、2 capability関数、capture不変triggerを追加し、既存2 CHECKを1 CHECKへ置換する。既存行UPDATE、給与refresh、既存勤務日関数置換、storage変更、有効会社INSERTはない。全体transactionに入れなければ、CHECK前提拒否より前のADD COLUMN/tableが残り得る。

旧行は7列すべてNULLのまま旧CHECK相当の枝を通す。新v1 INSERTは会社rollout enabledが必要。UPDATEは旧または新versionが非NULLのとき14生証拠列の変更を拒否するので、旧行への後付けv1やv1の消去も拒否する。これはDELETE禁止ではない。daily_report_id更新はcapture guardから許可されるが既存勤務日guardの会社・現場・ルート・勤務日照合を通す必要がある。

BEFORE INSERT/UPDATE の同種triggerは名前順で `attendance_capture_contract_guard` → `attendance_shift_evidence_guard`。前者はcapture列を変更しない。後者がwork_dateを計算する。ほかの実trigger、confirmed_atのdefault/trigger、列ACLを適用直前に保存・確認し、repo fixtureだけで本番と同じと判断しない。

## 有給との交差

`20261008200018_paid_leave_wage_contract.sql` は attendance_entries/paid_leave_requestsを給与計算に使用するが attendance_verifications/capture列を直接読書きしない。#782単独適用がこの給与処理を発火させるDMLはない。

ただし既存 `public.force_manage_attendance(text,jsonb)` は勤務変更・休み・有給処理で対象勤務の attendance_verifications をDELETEし、attendance_entries/paid_leave_requestsを変更する。日報メンバー除去・日報DELETEまたはdraft化も行う。したがって有給計算の成功はv1生記録と写真保持の成功を意味しない。勤務修正→有給、既存有給→勤務、翌朝退勤付き勤務、日報写真リンク済み勤務、給与確認済み明細を隔離環境で組合せ検証する。保存済み原記録・snapshot・写真の必要な保持/アーカイブは削除経路ごとに確認する。

## 適用直前の限定snapshot

| 対象 | 保存内容・比較 |
| --- | --- |
| attendance_verifications | 全対象行と列/既定値/列ACL、CHECK/FK/index、全trigger定義・OID・enabled、owner/tableACL/RLS/policy。新7列不存在と置換対象2 CHECKの正規化式を確認 |
| 勤務・日報関連 | daily_reports/daily_report_workers/attendance_entries/paid_leave_requests の必要な関連行とFK/trigger、source_clock_in_id自己FKおよびvehicle FK削除動作。raw給与・写真情報を公開repoへ保存しない |
| 実行関数 | validate_attendance_shift_evidence、guard_daily_report_shift_identity、force_manage_attendance、日報写真link/RPC、account_access_allowed、勤怠権限関数。pg_get_functiondefとsignature/owner/ACL/search_path/secdefを保存 |
| 新有給・角印 | 直前の給与関数・帳票snapshot trigger/ACLおよび保存済み明細を比較baselineへ含める。変更が不要な関数を巻き戻さない |
| Storage | attendance-evidence bucket設定、storage.objectsの必要metadata/owner/参照関係、policyと削除/archive関数。metadata snapshotは写真bytesのbackupではない。bytesの保管・復元確認は別 |
| deployment | migration履歴version/name、source SHA256、旧capture/journey不存在または現行定義、全rollout行。既存GPS勤務日の異なるledger番号を埋め直さない |

適用時は同transactionで対象をロックし、取得snapshotとの変更有無とCHECK前提を再照合する。OFF schema適用後も旧列の全行内容、給与/帳票、既存trigger/ACL/RLSと関数の保持を照合。新rolloutは0有効行、新private表RLS/ACL、未認証・他会社capability拒否を確認する。失敗時transaction rollbackで新列/表/関数/triggerが残らないことを確認する。

## 有効化を止める条件

既存attendance-evidence UPDATE/DELETE policyと管理RPC削除経路の保持保証、会社/worker/source削除cascade、アカウント削除archive、送信不明draftの写真保持、放置upload回収が未確定ならcapture/journey両gateをOFFに保つ。schema適用とONは別判断。写真置換/削除policyの修正はこのレビューに含めない。旧GPS migrationの再適用、履歴書換え、旧NULL推測backfill、保存済み生証拠の変更を復旧方法にしない。

本書はsourceレビュー完了のみ。最新本番snapshot取得、隔離全chain検証、本番DDL、gate ON、実iPhone操作完了を主張しない。
