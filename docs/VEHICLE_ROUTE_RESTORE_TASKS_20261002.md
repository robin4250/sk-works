# SKO 車両・ルート復旧タスク — 2026-10-02

## 車両
- [x] 表示名を登録
- [x] 車両番号を登録
- [x] 走行距離を登録
- [x] 車検証を PDF / 写真 / カメラで登録
- [x] 自賠責保険を PDF / 写真 / カメラで登録
- [x] 任意保険証書を PDF / 写真 / カメラで登録
- [x] 3書類がそろわない新規車両は保存しない
- [x] 車両書類は private Storage に保存

## ルート
- [x] ルート名
- [x] 現場名の選択または住所入力
- [x] 地点は何件でも追加可能
- [x] 備考
- [x] 旧仕様の運行日・運転者・固定1現場は新UIから除外

## 権限 / ON・OFF
- [x] 車両・ルート登録/編集は管理者・サブ管理者のみ
- [x] 本番RLSも owner / admin / manager のみに制限
- [x] 管理者の会社機能ON/OFF対象へ追加
- [x] OFF時はホーム・メニュー・本日の勤務報告から車両・ルート導線を非表示

## 本日の勤務報告 / 勤怠
- [x] 「出勤方法と現場を選択」の直下に同系統サイズの「車両とルートの選択」
- [x] 車両とルートはそれぞれ未選択に戻せる
- [x] 選択時だけ「選択中の車両」「選択中のルート」を表示
- [x] 当日単位で選択し翌日に自動持越ししない
- [x] 出勤・退勤レコードへ選択車両/ルートを引継ぎ
- [x] 退勤後に日報入力を開く

## 日報 / 走行距離
- [x] 日報の社員ごとに車両・ルートを表示
- [x] 車両選択時だけ走行距離欄を表示
- [x] 「メーターを撮影して読取」でiPhoneカメラを起動
- [x] ML Kit OCRで数値候補を抽出
- [x] 読取結果を本人が確認・手修正可能
- [x] 合わない時は再撮影可能
- [x] 日報保存時に確認済み走行距離を車両マスターへ更新
- [x] 現在の走行距離より小さい値は本番DB側で拒否
- [x] A4日報PDFへ車両・ルート・走行距離を明記

## 最終確認
- [x] Flutter CI — PR #497 final HEAD: success
- [x] iOS CI — PR #497 final HEAD: success
- [x] Secret Scan — PR #497 final HEAD: success
- [x] 本番Supabase migration整合 — vehicle/GPS/employee restore migrations verified present
- [x] Releaseビルド（CI / no-codesign）— success
- [ ] 署名済みReleaseを対象iPhoneへインストールして単体起動
- [ ] iPhone実機で車両登録3書類
- [ ] iPhone実機で複数地点ルート登録
- [ ] ホームで車両/ルート選択・解除
- [ ] 出勤→退勤→日報へ引継ぎ
- [ ] 実機カメラOCR→数値確認→走行距離更新


## 2026-10-02 final automated gate snapshot

- main: `acefae39be782c5342ab7e34ab1378aaf9f17002`
- Restore integration PR: #497 merged into main.
- Flutter CI run 1708: success.
- iOS CI run 1130: success (includes iOS Release build without codesigning).
- Secret Scan run 3062: success.
- Production Supabase contains the vehicle/route, GPS auto-attendance, and employee personnel restore migrations.
- Final restore completion remains blocked on signed Release installation and the physical iPhone route; do not mark restore complete before that.
