# 週間・カレンダーの勤務詳細（未配布候補）

Base main: bc25bfd4475f2ff5eeb6023bcafb842970a1700d。
ローカルFlutter/Dart、本番DML、main統合、Release作成は未実施。

## 切り分け

- 最新mainの週間表には残業・早出・夜間・手当タグが既存実装済み。ただし横スクロール1列で右側の項目が隠れる。
- カレンダーには手当名の表示はあるが、残業・早出・夜間の表示コードがない。
- worker repositoryはbuild21(ff591)と最新mainで一致。確定attendance_entriesとsigned日報の登録手当snapshotだけを読むため、仮保存の日報にだけある手当は表示元に入らない。
- 2026-10月の本番をread-only集計（個人ID・名前・署名本文は取得せず）した結果、draft worker2行に会社手当選択があるがlinked attendanceは0。signed worker2行/attendance2行には会社選択/手当名/残業がない。confirmed facts1行もdraftで、手当あり・残業/早出0。残業値が存在するとの断定はできない。

## 変更

- 週間タグは折り返し、自然な高さへ。残業/早出/夜間は時間単位を明示する。
- カレンダーへ確定attendanceの残業/早出/夜間を追加する。
- 月内・対象workerだけの保存済draft日報を読み、『日報未確定』の別参照欄に保存時間と登録名を表示する。別report/date/worker、重複、負/無限時間は拒否。
- 保存済の登録ID/name/versionはselectionモデルで保持。数量を持たないselectionに1時間などを補わない。
- draft詳細はattendance確定時間/金額/日数/月合計/PDFへ加算しない。給与・請求反映の基準を変更しない。

## 検証

専用widget/境界/Mock HTTP取得テストを用意。CI未実行。既存RLSや認証は変更せず、保存データを作成・修復しない。対応版のiPhone表示は未確認。
