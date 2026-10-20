# 友達一覧からのSKO招待入口

基準075b4004、担当F。通常の友達管理画面にはアプリ招待入口がなく、個別チャット相手選択時だけ「追加」→「電話番号通知」から既存AppReferralPageへ進む実装だった。通常の友達管理と個別チャット選択の右上に「SKO招待」を追加し、既存callback/source friend_add/友達紹介用配布gateを再利用する。グループメンバー選択では表示しない。既存の電話番号通知経路は維持する。画面内「？」ヘルプとchat局所英訳を更新。

新入口は読取中/処理中/actor無効化時に停止し、処理開始前のactor/epoch照合、連打抑止、復帰後の一覧再読込を既存方式で行う。招待を開けない例外は現actorにだけ通知する。既存履歴・composer再試行、RPC/SQL/Auth/provider設定は変更なし。

## 検証

- Dart formatter --output=noneで3変更Dartファイルの構文読取成功。flutter_lints未解決警告あり、analyze成功とはしない。
- 既存tool/test_app_referral_rpc.mjsをPGlite0.3.14隔離fixtureで実行し成功。feature gate/owner隔離/Master/URL検査/正直な配達状態/クライアントからの紹介元・points書込拒否を確認。現本番API成功を証明しない。
- 既存widget fixtureに通常/個別チャットでの直接入口、連打1回、復帰再読込、actor変更後停止、グループ選択非表示の3testsを追加。Flutter起動は親担当の自動承認拒否を保持し未実行。
- git diff --check成功。

## 残る条件

- 配布channel APIの導入状態、機能ON、正式URL、本人利用権限は本番未照会。現AppReferralPageはfriendInviteを公開版publicへ固定する。既存review-only backendもkind friendをpublic限定にする。所有者iPhoneのTestFlight更新成功を友達用公開URLのreadyと混同しない。本修正でgateを開放しない。
- 招待の準備/履歴作成/本SMS作成画面/送信/登録/友達承認は別工程。SMSを開いただけで配達・登録成功と表示しない。画面の再送失敗は既composerが同一準備を再利用するが、全端末/全再送にまたがるサーバー重複抑止やexpiry消費を今回追加・証明していない。
- 社員QR初回登録と一般アプリ紹介を混同しない。承認済み友達を作る本人確認/紹介元確定/point付与は既画面で未接続表示のまま。
- Google/Face IDを変更しない。panel_sevenのsourceではFaceIDは端末内確認、Apple追加は提供条件付き、電話番号追加は準備中。実Google/Apple/電話ログイン、既存本人/company/role復帰は実機未確認。
- 本番接続/外部招待/push/配布は実施なし。UI入口の修正を実機の招待送信完了とは扱わない。
