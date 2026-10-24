# 当日の最終退勤と実勤務時間原本を結ぶscope候補（2026-10-25）

## 今回の前進

旧診断を繰り返すのではなく、実際のサーバー原本から「全勤務が閉鎖済みで、指定日報が最後の勤務の退勤に結び付いているか」を判定する読取専用候補を実装した。

候補schemaは checkout_paid_hours_candidate_private。公開RPC・client grantは作らない。既存runtimeや本番DBへ適用せず、既存の会社手当名保護 ac08fbea5766d279f8bf764a0744e089 も変更しない。

**この段階では時間入力欄・二署名の時間証拠ledger・給与数量はまだ接続していない。** scope候補を作ったことと、時間手当が給与へ反映したことを区別する。

## 実sourceの対応表（業務行を読まないcatalog確認）

| 役割 | 現在の正本 | 判定と注意 |
| --- | --- | --- |
| 勤務開始と退勤 | public.attendance_verifications | clock_out.source_clock_in_id が exact clock_in.id を参照。会社・worker・site/route・vehicle・work_dateも一致する |
| 1勤務1退勤 | attendance_verifications_one_out_per_start unique partial index | source_clock_in_id非nullの終了原本を一意化 |
| 証跡の整合 | private.validate_attendance_shift_evidence() MD5 e1d6e6a1b8da732d8bcf5f55d3f1374b | 時系列／所属／勤務先・canonical work_date・同刻退勤拒否。更新時にidentity/time/sourceの変更を拒否 |
| 日報への結合 | private.link_daily_report_attendance_evidence(uuid) MD5 c406a799eebc41b7d5fa5abffc394eb4 | Repository.saveDraftはこのRPCを実行。会社／site／route／canonical日付で未リンク証跡へdaily_report_idを保存。近い時刻の推測ではないが、worker一覧に限定する追加保証ではないのでcandidate reader側でworkerを必ず限定 |
| 日報の社員 | public.daily_report_workers | 指定report_idに対象worker_idが存在することを再確認 |
| ルート途中の現場 | private.route_journey_captures / private.route_journey_visit_events | source_clock_in_id・route_stop_id・start/end captureのexactペア。moveでendになっても全勤務の退勤とは限らない |
| 最後のルート現場と退勤 | private.route_journey_visit_before_clock_out() MD5 7d52106e169225a400e5fef63841e7a8 | clock_out INSERT内で最後のvisitをendにし、そのcapture_idへNEW.idを使う。未訪問stopが残れば退勤を拒否する。guardのactual bodyをfixtureで再利用 |
| 訪問別日報 | private.route_visit_reports | 通常のpublic.daily_reportsとは別の保存先。到着／移動captureペアへ紐付く。途中の日報を最終日報扱いしない |
| 通常日報の二署名 | private.save_daily_report_signature(uuid,text,text,jsonb) MD5 40f29d53008e6bf5610ce25e5fa96ef3 | draftで報告者／責任者を保存し、両方揃うとpublic.sign_daily_reportへ渡す |
| 最終署名と勤怠 | public.sign_daily_report(uuid,text,jsonb) MD5 a433ab29499da6e50ba930a5d3243957 | 両署名確認済みtyped価格receiptをcapture後、attendance_entriesへsource_report_id/receipt pointerと同じ行で反映。正常実勤務時間を現在は保存しない |
| まとめ退勤 | mainのGroupCheckoutRepository / staged SQL | group_checkout_candidates/commit_group_checkout/attach_group_report_sourcesはmain候補にある一方、本番catalogには未導入。今回それを既実装・利用可能と仮定しない |

private.report_clock_ids は既存の時刻ベース互換補助で、exact source_clock_in_idの代わりに使わない。日付だけの一覧も最終勤務の権威にはしない。

## 新readerの契約

read_closed_day_scope(company_id, worker_id, work_date, report_id) は、clientのfinalフラグや入力時間を受け取らない。server原本を読む。

- auth.uid・account_access_allowed・会社membership・worker所属・reportの会社／日付／社員を検証。
- 当日のclock_in全件と、source_clock_in_idで一意に結合するclock_out全件を列挙。
- legacyでexact canonical日付／終了pointerがないもの、未閉鎖、複数終了、会社／社員／勤務先不整合、同日勤務区間の重なりはblocked。
- serverの終了原本confirmed_atで最後を選ぶ。同時刻の候補が複数なら任意IDを選ばずblocked。
- 最後のclock_in/outのdaily_report_idが指定日報に一致し、日報headerのsite/routeも一致することを要求。前の現場日報は拒否する。
- routeは未終了start・未訪問stop・終了証拠欠落を拒否し、最後のend captureがexact clock_out.idへ結合することを要求。
- 原本集合・report結合のSHA256 fingerprintを返す。日報statusの署名前後だけでは物理証拠のfingerprintが変わらない。
- 最終日報の手当選択は見ない。最終で時間手当が未選択でも、日時間証拠を確定できる土台とする。
- 同日再出勤で集合fingerprintが変わり、未退勤中はblocked。再退勤後は新しい本当の最終日報だけが適格になる。
- elapsedや8hから時間数量は作らない。paid_hours_calculated=false / daily_quantity_connected=falseを明示して返す。

readerは原本の整合判定であり、時刻を賃金上の対象時間に変換するものではない。

## 既存routeでの保留条件

現行最終guardは、最後の訪問がactiveならclock_outと同時にendを作る。既に最後の訪問もmoveでend済みで、その後に退勤したケースではclock_out.idとend captureの結合がない可能性がある。今回のreaderはその場合をroute_final_end_not_clock_out_boundとして安全側に保留する。

古いroute証拠が未登録／機能OFFの勤務にも、時刻や最後のstop名からfinalを推測して補完しない。該当ケースを本番互換済みとは扱わない。

## 隔離Native検証

tool/verify_closed_day_paid_hours_scope.mjs はPostgreSQL17のempty localhost fixtureにだけ接続する。実productionの証跡行は使わない。

exact bodyを再利用するのはvalidate_attendance_shift_evidenceとroute_journey_visit_before_clock_out。会社membership／auth wrapper／route endの保存helperは明示した合成fixtureであり、本物のGoTrueやRLS全体の証明とは扱わない。

確認対象：

1. 未退勤をfinalと呼べない。
2. exactな閉鎖pair1件／複数件をserverから列挙。
3. 前の日報はfinalを名乗れず、本当の最後のreportだけ適格。
4. unchanged readと署名status変更でfingerprintが安定。
5. 同日再出勤でfingerprint変更・保留、再退勤後の最終reportへ更新。
6. 最終reportに時間手当選択がなくてもscopeは確認可能。
7. route途中の退勤はactual guardが拒否してrollback。
8. actual最終route guardがclock_out.idとvisit endを同時保存。
9. 同刻退勤・重複終了・証跡時刻書換え・他社／別社員の利用を拒否。
10. 重なる勤務証拠を合算・推測せず保留。
11. private readerはauthenticatedへ公開せず、既存guard bodyを変えない。

remote CI前のNode構文確認のみ実施。Native成功を得るまでSQL接続確認済みとしない。

## この先の最小候補

次はscope fingerprintを、明示入力した日合計・報告者／責任者の二署名へ結び付ける。

1. 最終退勤日報で明示時間（空欄null、明示0は0）と上記server scopeを保存し、report_basisへ含める。
2. 二署名の直前に同scopeを再確認してlockし、privateな日単位時間証拠ledgerへimmutableで保存する。最終reportのhour選択有無でcaptureを省略しない。
3. month resolverは現在の全勤務集合とledger scopeを比較し、適格な日証拠を1件だけ選んで当日のimmutable価格receiptへ数量を供給する。
4. 新規clock-in/out・証跡置換・日報修正が生じたとき、未確定給与へ再計算／blockedを伝える。確定済みは保存済みsnapshot保持。
5. after署名直後に同日再出勤が入り込む競合も、署名・勤務開始双方の同じserver scope lockで検証する。

今回のreaderはread-onlyの瞬間snapshotで、phantomの新勤務をロックする仕組みではない。これをそのまま量の確定RPCへ流用して競合対策済みとは言わない。原子性・二署名・失効・時間×登録単価・給与/PDFの接続を次の別候補で検証する。
