# 招待・ログイン：main ab9統合後の残条件

基準main `ab9e13fa77abb0a630c00c8ce917bae62c60f575`。本資料はsource/CIの読取確認。Mac/iPhone操作、他者招待・SMS、ログアウト、provider照会・変更、Auth/RLS/会社所属/役割変更を実施していない。

## 1. 「招待」を3系統に分ける

| 系統 | 現source | 残る確認 |
| --- | --- | --- |
| 友達一覧→SKOアプリ紹介 | 通常/個別チャット用友達一覧にSKO招待入口を統合済み。狭幅・拡大文字ではtooltip付きicon。既存AppReferralPageへfriendInvite=trueで進む | 新Release→本人iPhone表示。実公開URL/利用権限/gate/稼働RPCは未照会 |
| SKO IDでの友達申請/承認 | `send_sko_friend_request` / `respond_sko_friend_request`と確認dialog。actor/epoch保護、busy、承認後一覧再読込を実装 | 実相手の申請・承認・accepted後の個別トーク。アプリ紹介送信だけで友達acceptedにはしない |
| 従業員の初回QR登録 | main scannerは`type=sko_employee_invite`のphone/password方式。create-employee-invite Edge Functionを使用 | 別PR #1308は認証済みUID方式v2のreview-only候補。scanner/発行UI/capability/Storage/実HTTP/JWTなどは未接続 |

## 2. 紹介のsubmit/retry/期限/accepted

- `AppReferralRepository.load`はapp_distribution_snapshotを読む。PGRST202だけ旧snapshotへfallbackし、権限拒否ではfallbackしない。
- friendInviteはdistribution channel `public`へ固定する。TestFlight本人更新成功は公開友達招待readyではない。公開前・正式公開URL未登録ではSMSボタンを有効にしない。旧backendしかない場合も友達紹介は送らない。
- prepareDistribution(name,phone,channel,kind)→既存composerで`SMS:` URL起動→recordComposerOpened。履歴は「準備」「作成画面を開いた」と実送信/配達/登録を分ける。
- composer起動失敗では同一actor/name/正規化phone/friend/channelの準備済み招待を画面内で再利用。履歴記録だけ失敗した場合はSMSを再起動せず「履歴を更新」で記録だけ再試行する。画面破棄・入力変更・actor変更で旧準備を使わない。全端末にまたがる重複排除の保証ではない。
- page actor scopeはA→B→A、stream error、disposeで無効化し、入力/履歴表示を破棄する。既にサーバーへ送信済みの処理取消保証ではない。
- 一般アプリ紹介はログインcredentialのQRではない。現クライアントには紹介をredeem/consumeしてacceptedにする操作を追加していない。招待リンクの到達/紹介元確定/points/登録完了通知も未接続として表示する。紹介履歴のregistered_atを、今回の端末による本人登録確認と読み替えない。
- 初回QRの期限・取消・既使用拒否は別系統。mainの初期password変更前にはemployee_onboarding_state/status/期限を確認するが、Authパスワード変更とmarker記録は別リクエストで原子的な期限保証ではない。これをUIだけで解消済みにしない。
- PR #1308 v2のledger/profile/approval候補はexpired/cancelled/redeemed別actor・session/request/旧employee状態を拒否し、同一scope receipt retryを区別する設計。ただしdraft/review-onlyでmainアプリへの接続ではない。

## 3. Google / Face ID / Apple / 電話

| 対象 | 現sourceの実装 | 未確認/未接続 |
| --- | --- | --- |
| Google | 既存iOS OAuth callback `com.skworks.sko://login-callback/`。session UID/accessToken一致と既存membership読取後だけ通常画面へ進む。company/roleへの書込・identityコピーは行わない | 実Google選択/callback/同じ本人UID・会社・role・既存データの復帰。別Googleを選んだ場合の新UID作成はclient membership確認だけでは防止できない |
| Face ID / Touch ID | 重要情報を開く端末内本人確認。provider identity linkingや電話番号所有確認とは分離表示 | 本人iPhoneでの実生体認証と復帰。Google/Apple/電話のserver本人証明とは扱わない |
| Apple追加 | 現mainにはAppleAccountLinkCard/AppleAccountLinkが存在。実settingsのexternal.appleを読むgate、server getUserによるUID検証、既存Google identity・会社role集合の前後一致、5分以内oauth AMR、session/世代/取消保護を持つ | 本番provider/Manual Linking/Apple設定/secret有効性は今回未照会。実Apple本人同意・同UID完了・Googleと会社role維持・Release callbackは未確認 |
| Apple通常ログイン | `OAuthProvider.apple`の現lib参照は既存アカウントのgetLinkIdentityUrlで、通常Apple signInの入口とは別 | Apple identity追加と、ログアウト後にAppleで同一UIDへ再ログインする完成を混同しない |
| 電話 | 旧電話+passwordの通常/初回QR導線はsourceに存在。アカウント設定の電話番号追加は所有確認準備中 | provider/実SMS/番号所有の追加確認は未確認。番号登録・FaceID・既存Googleだけで番号所有確認済みとはしない |

Appleの「直近Google」説明は、実コードではserver検証済みuserのGoogle identity保持と直近oauth AMRを確認するもの。AMRのoauthだけで今回のproviderをGoogleと特定したとは扱わない。画面の確認文は直近の「外部アカウント認証」と区別している。

## 4. CI証跡と範囲

- PR #1309 head `1f3c2288fe6b34971c6b7e0171ff209d07115dbd`はmerge済み（main ab9）。Chat display regressions run `39503267974` / job `118905785660`：解析step6、test step7ともsuccess。通常友達入口/個別チャット入口/グループ非表示/連打/actor変更の追加3tests、既存狭幅320px・文字1.3倍English、friend操作session suiteを含む。
- PR #1308 head `911628d8dca0371209f3f19560ef74e17ffe3146`はopen draft。Authenticated employee invitation review-only integration run `39414326444`のprofile job `118599524240`、approval `118599524432`、ledger `118599524560`はいずれもsuccess。fixture証跡であり本番導入・v2クライアント・実provider確認ではない。
- PR #1280 head `80ee7ffd7bc42449206deaa97836940d76fa387e`はopen draftの設計資料。過去の基準mainで記載した「Appleアプリ導線未実装」を現mainへそのまま転用しない。現mainには上記の条件付きApple追加実装がある。過去に観測したprovider状態も現在の有効性の証明ではない。
- PR #1309取得結果はworkflow一覧先頭ページの取得。Apple/Googleの専用workflowは変更path条件であり、このPRで専用runが再実行されたとは主張しない。統合後mainの全CI成功と個別PRhead CI成功も別記録にする。

今回の追加製品コード変更は0。独立して直すべき新しい実装欠落と断定できる箇所は発見していない。上記の本番設定・配布・実機/E2E条件を未完として保持する。
