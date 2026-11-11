# 共通時間手当：ルート日報の時間源診断と最小接続設計（2026-10-25）

## 状態と所有境界

これは独立候補の診断と設計であり、実労働時間の接続済み実装ではない。本番へのDDL・業務行変更は行っていない。日単位の給与Releaseをこの候補で止めない。

main `bde1780bf897ae01e9224c7b9e709c0bb1a4a1f5` の既存sourceを参照し、本番catalogの関数定義だけを照合した。guard_receipt_pointer の適用済み会社手当名保護 `ac08fbea5766d279f8bf764a0744e089` を必ず保持する。旧 `e6c537…` guardに戻さない。

今回の追加ファイルは診断fixture、診断wrapper、専用CI、本文書。既存日報UI・RPC・給与計算をまだ変更していない。

## 再利用した既知の結論

- 単価設定の base × hoursPerDay（既定8）は単価換算であり、実勤務時間ではない。
- attendance_entries.regular_hours は既定0で、現在の署名処理は正常な通常実勤務時間を保存していない。
- clock-in/outの経過、人工×8、残業等の既存入力、月別manual_hoursを通常の実労働時間として流用しない。
- 休憩・移動・端数等の扱いを決めずに自動推定しない。
- 入力なしはnull／計算保留。実際に0と入力された場合だけ0という別状態。
- 共通時間手当は、登録済み単価と署名済みの対象時間を掛ける。顧客単価・会社率・架空の額を作らない。

## 現契約と具体的な不足

1. DailyReportWorkerDraft.toRpcJson は残業／早出／夜間・手当ラベル・typed選択を保存するが、通常の実労働時間を持たない。
2. report_basis は上記日報内容を署名scopeへ含めるが、時間源がない。
3. capture_report は両署名を要求し、選択時点の会社登録価格を私的なimmutable receiptへ保存する。company_allowance_selections がないreportはcapture対象外。
4. receipt snapshot は contract_version・work_date・itemsのみで、通常実勤務時間や最終退勤の原本IDを含まない。
5. aggregate は同一社員の同一日・同一項目を1回にまとめ、hourは明示的に actual_work_hours_unavailable / quantity=null / amount=null として保留する。
6. resolveは勤怠に結び付いた価格receiptだけを取得する。勤務終了日の独立した時間原本を読む接続がない。
7. 画面側には sourceClockInId / sourceClockOutAt があり、group checkoutは実際のanchor IDと退勤結果を照合する。一方、これらを日報の時間源として署名scopeへ固定するサーバー契約は現状ない。clientのfinalフラグだけを信頼してはならない。
8. route訪問の日報は sourceClockInId・routeAssignmentId・routeStopId・arrival/moveのcaptureペアを使う。途中のmoveは当日の最終退勤ではない。

## 診断fixture

`tool/probe_checkout_paid_hours_route_gap.mjs` は既存118項目のsource-bound PostgreSQL17 fixture（SHA256 a9588f8af73dee8c89cfcd81d7ba72e3f0f8d6208b736429f90b83da9449a73a）を変更せずラップする。

同じ社員・日付で現場1と現場2の日報を作成し、それぞれ二署名で確定する。最終側だけ paid_work_hours='7.5' という未知payloadを加えても、現行サーバーは時間原本へ保存しない。結果は次のとおりでなければ診断失敗とする。

- 両receiptの時間のないsnapshotは同じまま。
- month resolverのhourはblocked、quantity=null、amount=null。
- actual_work_hours_unavailable の理由を保持。
- 後の日報で先の日報のimmutable価格receiptを書き換えない。
- ac08の会社手当名保護guardがそのまま維持される。

これは2現場のsource-bound保存／署名／給与resolverを使う診断であり、fixtureは実際のroute終了clock-outを捏造しない。**実退勤との最終日報結合の証明ではない。緑なら未接続を再現しただけで、修正完了を意味しない。**

## 全現場に日合計を入力する案を採らない理由

途中の現場終了時点では当日の合計が未確定である。後の最終日報だけに合計を入れると、前の署名済みreceiptには時間がない。現状aggregateにそのまま各receiptの時間を要求すれば永続的な保留となり、最初の現場まで修正・再署名を繰り返す運用になる。

逆に各現場の入力を足すだけでは、入力が日合計か現場区間か、区間の重複がないかを証明できない。同じ日の8時間を2枚に入力して16時間へする実装を避ける。

## 最小接続候補：最終退勤後に日単位の時間原本を1回確定

以下はまだ正式実装ではなく、安全根拠を揃える必要がある契約案。

### 1. 入力と最終退勤scope

最終退勤後の日報で、社員ごとに「当日の休憩を除いた実勤務時間」を1回明示入力する。残業等の扱いと有給／移動等の対象外時間は、通常の勤務実績と別の説明で明示し、未決の区分を勝手に含めない。

入力は0〜24時間の有限小数（上限小数4桁候補）、空欄null。必須入力エラーと、実際の明示0を区別する。

clientは時刻や完了状態を正本として送らず、保存済みsource clock-in / clock-out / route終了証拠のIDを送る。サーバーが次を読み直す。

- 本人／会社／対象社員／canonical work_dateが一致。
- anchorが本当にその勤務の開始原本で、結び付く正式clock-outがある。
- arrival/moveの途中captureではない。
- 同社員・日付で未退勤勤務や未完了routeが残っていない。
- 同日に複数勤務がある場合はすべての対象勤務を明示して閉じた集合を固定。どれか1件を任意に採らない。
- 上記のscope fingerprintを日報basisへ入れ、報告者／責任者の両署名へ含める。

現行保存経路にこのサーバー結合がないため、clientフラグを追加するだけでは進めない。

### 2. 時間原本と価格receiptを分離

両署名完了時に、会社・社員・work_date・対象勤務集合・日報ID・scope hash・明示時間・署名revisionから成る私的な日単位時間証拠を保存する。価格receiptは元のまま保持し、過去receiptへ時間や新単価を書き込まない。

最終日報で時間手当を選択していなくても、その日途中で選ばれた時間手当へ日単位時間を供給できる必要がある。したがって現capture_reportの「typed選択なしは即return」と別のcapture contractになる。

1日について有効な時間証拠が複数・矛盾なら保留。明示0は有効な0として扱う。失効や訂正の履歴を削除せず、正規の再承認・再署名で新revisionを作る。

### 3. resolverから給与・PDFへ

month resolverが社員・日付で時間証拠を一意に解決し、当日の選択済みimmutable価格receiptのhour項目へ数量を供給する。同一日・同一項目は1回、dayの既存集計は変えない。価格snapshotが同日で矛盾する既存保留も維持する。

入力なし・署名不足・scope不一致・退勤未確定・時間証拠失効はnull／blockedを維持する。月次published hourのmanual quantityを同じものとして足さず、既存dedupeを確認する。

現在のcustom earnings/deductions→税→net→保存detail→画面/PDFの共通計算経路へ流す。明細だけ額を足したりPDFだけ時間を表示して完了にしない。

### 4. 後の勤務変更に対する失効

当日の時間証拠を確定した後に同日の勤務開始／退勤／route証拠／所属／日報が変更された場合、そのscope fingerprintが現在の勤務集合と一致するか再評価する必要がある。古い証拠で新しい勤務時間まで計算しない。

失効は旧signed証拠や価格receiptの削除ではない。未確定給与は再計算・保留とし、既確定給与は保存済みsnapshotを保持する。再び署名を取り直す正規導線を用意する。

ここを無視すると、後から同日再出勤した場合に「当日合計」を以前の7.5時間のまま採用する不整合になる。

## 実装着手前の必須隔離検証

- 途中現場日報には時間なし→最終退勤後に1回入力・二署名→途中のhour選択にも適用。
- 最終日報にはhour選択なしでも独立時間証拠を読み込める。
- 同日同項目複数receiptの重複0、異なる項目は各登録単価で計算。
- 日／月／legacyの元結果不変、未確定のgross/deductions/net/detailとPDF一致。
- 複数勤務／route途中／未退勤／別会社／別社員／偽のfinalフラグ拒否。
- 入力null保留、明示0、負数、上限超え、NaN、過剰桁拒否。
- 入力・対象勤務集合の変更で署名scope失効。
- 確定後の再出勤／退勤訂正で時間証拠再評価、過去確定帳票不変。
- 旧receiptのhash不変、直接authenticated編集不可、ac08guard保持。
- 正式GoTrue/PostgRESTの本人権限と状態遷移で確認（合成GUC試験だけで本番認証済みとは扱わない）。

## 実装の判断

新しい時間原本と最終退勤scopeを確実に結ぶ契約は、日報の単一欄を足すだけではない。現時点ではその部分の安全根拠が不足しているため、runtimeパッチを先に当てない。まずこの診断proofをremote CIで実行し、最終退勤証拠の結合／失効設計を別候補で固める。

日単位の動作、月単位の既存条件、確定receipt、現在の署名・会社手当名保護を保持する。本番適用とmain統合はrootが別途判断する。
