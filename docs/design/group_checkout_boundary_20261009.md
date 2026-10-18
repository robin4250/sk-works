# 同一現場の代理退勤：実装境界案

2026-10-09 JST。読み取り確認の基準 main: a2a0ad26cebfbcc39ec99fe49f8b78d4ceb6c202。
本書は設計案。migration・本番適用・代理退勤機能の完成を意味しない。

## 現在の制約

- GPS勤務日migrationの `attendance_shift_evidence_guard` は出勤IDに退勤を結び、会社・本人・現場・ルート・車両を一致させる。出勤の勤務日を退勤へ継承する。
- `attendance_verifications_one_out_per_start` が1出勤につき1退勤を保証する。
- INSERT RLSは本人または勤怠管理権限。一般メンバーが他人の退勤を直接INSERTすることはできない。SELECTも本人・勤怠管理者が基本であり、全件をクライアントへ公開しない。
- 現在のverification_modeは manual/location/gps_auto/location_photoのみ。proxyは存在しない。location_photoには写真、位置モードには緯度経度が必要。代理人GPSを班員のGPSとして複製して制約を通してはいけない。
- 既存のまとめて修正RPC `submit_attendance_correction_request` は管理権限を要求する。メンバーの申請要件は未対応。これを会社全体の勤怠管理権限へ置き換えてはいけない。
- app_notificationsは本人通知のみ読取。private.enqueue_notificationには既存の重複キーがない。

## 最小APIとトランザクション

1. `group_checkout_preview(p_source_clock_in_id)` は入力者の実出勤をanchorにする。auth.uid・アカウント利用可否・現在の会社所属・active本人workerを検査し、会社/現場/work_dateをサーバーで取得。任意company/site/dateパラメーターを信用しない。
2. 同会社・同現場・同勤務日の実clock_inだけから候補を集計する。未出勤者を固定名簿で追加しない。route-only勤務はこの現場APIの対象外。work_date NULLの旧記録や同一人の複数候補は推測せず明示的に解決を求める。
3. preview返却は表示名・source ID・既存退勤状態・退勤時刻など最小限。GPS生値・写真パス・無関係な個人情報は返さない。入力者も対象勤務のメンバーである必要がある。固定班長を要求しない。
4. `commit_group_checkout(anchor_id, selected_source_ids, request_token)` が同じ所属・参加条件を再検査。会社/現場/勤務日ごとのadvisory transaction lockを取得し、clock_inをID順FOR UPDATE。自分の退勤RPCとも出勤行ロックを共有させる。新規clock_in側が共通lockを使わない限り、途中参加はpreview確定集合から除外して再読込に回す。
5. 既に退勤した班員は変更しない。早退時刻も維持。selected IDsは確定時点のanchor scope subsetでなければ全体失敗。本人未退勤と代理未退勤の新規退勤だけを挿入。時刻はサーバーnowを固定し、元勤務日を継承する。ユニーク制約衝突は成功済み状態を再読込する。
6. SECURITY DEFINERが必要な限定横断操作はprivate関数に閉じる。public wrapperは実施者本人チェックを必須にし、PUBLIC/anon EXECUTEをREVOKEしauthenticatedだけを付与。既存テーブルの一般SELECT/INSERTポリシーは拡張しない。private関数も本人・所属・account_access_allowedを明示確認する。

## 証拠区分

最小migration候補は `evidence_origin` (self/proxy) と `proxy_actor_user_id` を追加し、proxyはclock_outのみ・actorがcreated_byと一致・位置/本人写真の列をNULLに限定する。verification_modeへ正式にteam_proxyを追加するなら、既存GPS必須CHECKを名前と定義で調査し、proxyだけ例外化する。同時に証拠guardでorigin/actor/位置証拠の更新不可を保証する。旧NULL行へのバックフィルはしない。

別案はprivate proxy証拠tableでattendance manual行と1対1にする。ただしUIがmanualを本人入力と誤表示する危険があるため、専用originを読める全表示の更新を先に行う。どちらも元出勤GPSは変更しない。車両agentの排他triggerと共存するよう、proxy退勤のINSERTで運転手だけ車両利用終了を行う。

## 日報・通知

退勤と日報の確定は別段階。退勤で既存日報編集画面を開き、同scopeの実出勤メンバーを渡す。通知は日報の登録成功後、入力者以外の対象者だけへ送る。未保存日報で通知しない。

private outboxにはreport ID・登録revision・recipient user IDのユニークキーを置く。日報成功と同transactionでoutboxをINSERTし、app_notifications生成も同transactionなら不要なネットワーク処理を挟まない。再送workerを使う場合はnotification_idを保存し、重複防止と失敗再試行を管理する。通知action_idはその日報ID、work_dateはサーバーのreport_date。確認状態は別table(report, recipient, revision)で管理しread_atでは完了扱いにしない。

## メンバーのまとめて修正

新しい限定request RPCで同scopeの参加を検証し変更案・変更前snapshot・理由を保存する。現行の管理者修正RPCやテーブルの広いINSERT権限は付与しない。承認者1〜3人の既存設定を使用する。承認時はsnapshot/versionを照合し、並行変更があれば再確認。GPS原本を保持し業務値を修正する。既存force_manage_attendanceはGPS証拠削除置換を行うため原本保持要件にそのまま流用しない。

## 必須検証

同現場他社拒否、別現場/別月拒否、休み除外、退職/blocked拒否、複数start曖昧拒否、夜勤月跨ぎ、早退保持、本人/代理同時退勤1件、入力者自由、一般メンバーの他人直接INSERT拒否、proxy GPS未偽装、日報保存失敗時通知なし、再保存通知重複なし、既読と確認分離、承認前未反映、変更競合の承認拒否。
