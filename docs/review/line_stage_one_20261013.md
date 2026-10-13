# LINEトーク 第1段階

対象は既存LINE受信の復旧、受信テキストの保存、グループ別閲覧。出勤表・請求書への抽出/集計は追加しない。

## 確認した停止原因

- 2026-10-13 JST の本番 `line-webhook` version 10 は `LINE integration is paused` を200で返し、署名検証と保存に到達していない。mainのソースにはこの停止returnがなく、本番との相違。
- read-only集計では有効連携0、保存済みLINE本文0、raw受信イベント18。実投稿の保存確認は未実施。
- 元コードの `on_conflict=external_event_id` は本番の部分unique indexをPostgRESTから指定できない。実在する通常unique `(origin, external_event_id)` に合わせる。DBスキーマは変更しない。

## 実装

- HMAC検証後にrawイベントと本文を保存。DB/ネットワーク失敗は503を返し、LINE側再送の対象にする。raw保存済みでも再送時に本文保存へ進む。重複イベントは既存uniqueで1件のみ。DBの本文/エラー文字列をログに出さない。
- 既存管理者RPCで連携コードを発行。コピーした連携文をユーザーがLINEグループで送信する。アプリからLINEへの投稿/返信は追加しない。
- 「LINEトーク」で受信グループを選び、投稿者、日時、保存本文を表示。トークは標準機能として常時表示し、旧line_bridge OFFでも入口を隠さない。出勤表/請求書の個別ON/OFFは第2段階で扱う。既存チャットRLSを保持し、一般メンバー向けの新しい権限は作らない。
- 長いトークは1000行ごとに読む。連携停止後の保存本文も閲覧できる。停止中/連携前の過去投稿、画像/動画/スタンプは自動取込対象外。
- home/menuに専用入口。既存ヘッダー、給与、認証復旧、勤怠/請求抽出は変更しない。？ヘルプ更新。

## 検証

- Node: 署名、空の確認Webhook、本文/時刻保存、重複、raw/lookup/chat各失敗と復旧、ネットワーク、未連携、連携コード、非テキストの9テスト。
- PGlite 0.3.14: 本番と同じ通常unique+部分uniqueの下でraw成功/本文失敗→再送→正しい本文1件、重複1件を検証。
- Flutterの未ログイン表示と第1段階ヘルプの実widget testを追加。FlutterSDKはローカルにないためCIで検証する。

## 本番反映手順（実施は別記録）

1. 最新headの専用LINE/Flutter/iOS/Secret CIを確認し通常マージ。実際のmain sourceとCIのtreeを確認。
2. `get_edge_function`で現在version/sourceを再取得してversion10停止版から他作業が更新していないか確認し、現在sourceをバックアップ。
3. `line-webhook`にindex.tsとhandler.mjsをdeploy。LINE署名で認証する外部webhookなので既存のverify_jwt=falseを維持。サービスキー/チャンネルsecretは既存server envを使い、値を取得/出力しない。
4. 再取得source/versionを比較。署名なしPOSTが401でDB書込みに到達しないことを確認。
5. ユーザーが公式アカウントのいるLINEグループで連携文と確認用テキストを送信。受信raw/本文・1件表示・投稿者/日時を確認。実投稿はこの手順前に完了扱いにしない。

LINEのWebhook再送はLINE Developers側でONにする必要がある。こちらから設定変更/投稿はしない。停止中の投稿は200応答で失われており、過去のLINE本文取得APIはないため復旧後に新しい投稿で確認する。
