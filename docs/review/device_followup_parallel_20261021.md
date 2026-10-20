# build 6実機指摘・並走統合記録

基準 main d70b90b9f19f854e8f13c00c4a1e66fbfeb4235e。再fetch後も同SHA。Issue #273とopen PRを照合済み。#1307代表者プロフィール候補・#1308初回招待v2・#1280Appleログイン運用資料は既存別作業として保持。

## 作業所有

- A: expense専用docs/tool。共有payment repository/PDFは読取のみ。
- B: invoice勤怠根拠専用docs/tool。勤怠/給与DBは変更しない。
- C（統合担当）: payment_order、shared trade_document、invoice acceptance検証、共通ヘルプ/翻訳/CI、最終統合。
- D: 給与適用月の専用UI/repository/純粋結果型、給与専用検証とdocs。
- E: qualification写真baselineのreview-only patchと専用検証/docs。製品の削除再開なし。
- F: chat友達入口/局所翻訳/既存widgetテストと専用docs。Auth/provider/config変更なし。

各担当は別worktree/branch、共有部分はCだけが変更。主branchはfix/payment-order-work-defaults-20261021、既5040a61d/075b4004を保持して順番にcherry-pick。

## 検証と実機の境界

- A: v2読取clientは接続済み。本番OFF導入・negotiation・限定gate・exact旧draft変換が未完。catalogだけのinventoryを追加し隔離検証成功。金融row読取/本番接続なし。
- B: 既invoice SQLで2署名日+打刻のみ1日→2人工、正規根拠追加trigger→3人工、重複0、残業編集、確定保持を隔離再現。実対象の不足日補完は未実施。
- C: 工事名/場所の新規注文書連動、画像bytesによる意図しない縮小判定を修正済み。実resolver15項目を純粋Dartで成功。通常draftのacceptance生成とlocked時未添付通知を確認し、実機対象のlocked状態は未照合。PDF render/角印座標/会社情報不足は未解消。
- D: publish後の既勤怠INSERT/UPDATE triggerで共通日手当のquantityと給与再計算を確認。保険manual候補の既保存/CAS/明細/確定保持も隔離成功。本人実額条件/本番有効化は未確認。現契約は現在月以降で過去未確定月の訂正とは別。
- E: UIで見た後に増えた写真まで削除申請に含める旧候補の問題を再現し、ordered expected_photo_pathsをrowlock後に照合するreview-only補修。2modeと既認可/承認/履歴/Storage保持成功。本番・client送信導線は未接続。
- F: 通常友達画面のSKO招待入口追加。既callback/source/配布gateを再利用。既招待RPC fixture成功、3widget回帰を追加（未実行）。public配布URL未設定や権限でSMS作成不可の既制約は維持。実招待/ログインは未実施。

Flutter起動はcloud metadata宛通信で自動承認レビュー拒否済み。再起動/迂回はしない。独立した純粋DartプログラムはFlutterを起動せずローカル依存だけで実行。Flutter analyze/widget/PDF/Release/iPhone確認は未完。

GitHub送信は前回自動承認レビューにより明示的な外部送信許可不足で拒否・保留。別経路送信なし。本番DDL/DML/RLS/Auth/provider/権限/金融row修復、gate変更、他者招待、配布0。

iPhone更新・注文書表示・資格チェック非表示の実機成功は維持。修正/隔離検証のみで未完項目を完了へ移さない。

追加: Dのpublish receiptをserver件数表示へ接続し、非負整数/0/不明を区別。次の適用・月/形態変更・reload・actor/company/背景変更で旧件数と所有完了通知を隠す。純粋summary検証成功、SDK/widget回帰は追加のみ未実行。詳細ヘルプを更新。給与再計算件数は全員の実額反映完了を意味しない。

統合担当が既存CIへ今回の専用回帰を接続し、YAML構文・diff-check成功。遠隔CIは未実行。各worktreeのコミットは保持し、主branchへ競合なしで統合。

## GitHub送信後の追補

ユーザーの継続了承を受けPR #1309を作成。ローカル統合treeとremote treeの一致確認済み。前記送信保留は当時の履歴で現在は解消。初回CIでECRのpostgres取得がtoomanyrequestsとなったため公式postgres:17へ同majorの取得元を変更。解析指摘はchat async mounted/ifブロック、独立検証toolのpackage importとstdoutへ補修。空欄の工事名/場所はpayloadから除外し、旧serverでも既存文面を保存できるよう補強（非空の新設定にはbackend更新が必要）。純粋resolver検証は17項目成功。適用件数の所有完了通知はdispose後のframeで閉じ、無関係通知を触らない。
