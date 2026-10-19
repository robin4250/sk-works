# Appleログインを既存SKOアカウントへ追加する接続条件

確認日: 2026-10-20 JST。アプリ確認基準: main `d03753cdc2e14d48e860fb89e8662bdb1d730d3c`。
Apple providerの本番有効化も、Appleログインのアプリ実装も未完了。本資料は接続設計であり、本番利用可能の証拠ではない。

## 現状と実装範囲

- 現在のアカウント設定画面はApple追加を準備中と表示する。既存Googleログインは `com.skworks.sko://login-callback/` を利用する。
- 共有された本番設定確認ではApple providerは無効。Apple Team ID、Service ID、署名鍵、Manual Linkingの有効状態、実署名のApple entitlementは本担当では確認できていない。
- iOSディレクトリは生成対象。リポジトリにディレクトリがないことは、配布物にcapabilityがない証拠にはならない。native方式を採用する場合は生成処理と署名済み成果物を検証する。
- メール接続PRのAuth UI・repositoryとは重複編集しない。設定不足のままAppleログインボタンや利用されないhelperだけを追加しない。

## 既存Googleアカウントを保持する導線

1. 本人が登録済みGoogleで既存アカウントにログインする。サーバー検証済み本人UIDと既存会社所属を確認する。メール文字列や表示名をキーに所属を移さない。
2. アカウント設定内の明示操作「このアカウントにAppleを追加」で、追加対象UIDと目的を本人に表示する。既存の認証方法による直近の本人確認を追加する。Face IDだけをApple所有の証明にしない。
3. セッションに結び付いた `linkIdentity(OAuthProvider.apple, redirectTo: ...)` を使う。ログアウト状態の `signInWithOAuth(apple)` を追加操作の代わりに呼ばない。Appleの非公開メールはGoogleメールと異なり得るため、自動メール一致だけに頼らない。
4. 開始時UIDと操作世代を保持し、ログアウト・別UIDへの切替で完了表示を失効する。同じUIDへの戻りも旧操作を復活させない。OAuthから戻った後は新トークンを認めつつ、サーバーの本人UID・identities・所属を再取得し一致を確認する。ログを信用して完了表示しない。
5. 既に他UIDに連携されたApple、キャンセル、期限切れ、provider無効、Manual Linking無効は未完了。別UIDへ会社・従業員・権限をコピーしたり、本人アカウントを削除/統合したりしない。
6. Apple identityの追加後も既存Google identityを残す。氏名や連絡先・給与データをApple metadataで上書きしない。
7. 連携後のApple再ログインは同じUID・会社・役割・データで検証する。未連携Appleを初めてログインさせると新規UIDが作成され得る。アプリの所属確認はデータへの進入防止には使えるが、Auth側の新規登録防止にはならない。サーバー側の既存ユーザー限定方針/Before User Created hook等を別途設計・検証するまで、未連携ユーザー向けApple入口は公開しない。

## 管理画面で必要な設定

Web OAuthを利用する場合、Apple Developerの既存App ID `com.skworks.skWorks` にSign in with Appleを設定し、それに関連するServices IDを用意する。既存Bundle IDを変更しない。

| 設定箇所 | 入力・確認 |
| --- | --- |
| Apple Services ID / Website domain | `<project-ref>.supabase.co` |
| Apple Services ID / Return URL | `https://<project-ref>.supabase.co/auth/v1/callback` |
| Supabase Apple Client IDs | 実際に作成したServices IDを先頭。native方式併用時は実際のBundle ID audienceも許可する |
| Supabase Apple secret | Apple Team ID・Key ID・秘密鍵から作成した有効期限内のclient secretを管理画面へ直接設定 |
| Supabase Manual Linking | 設定変更前状態を保護して有効化。既存Google/メール/電話設定を巻き戻さない |
| Supabase app redirect allowlist | 既存 `com.skworks.sko://login-callback/` を厳密に維持。AppleのHTTPS Return URLとは用途が異なる |
| native方式を採用する場合 | Apple capability、`com.apple.developer.applesignin`、署名provisioning、nonce対応と固定SDKのnative identity linking APIを検証 |

`.p8`、client secret、access/refresh token、本人identity値はチャット・GitHub・テストログへ記録しない。OAuthのclient secretは最長6か月で更新が必要。期限前更新と失効時の既存Google復帰を運用に含める。nativeのみの方式はこのOAuth secret更新要件とは別。

## 完了に必要な実証

実際のApple設定と本人連携は未実施。次の検証までは利用可能・完了と表現しない。

- 固定Supabase Dart SDKの実HTTP試験で、未ログイン拒否、成功時UID不変、他UID既連携拒否、キャンセル、ログアウト/再ログイン競合、provider無効を検証する。
- 本人の明示的なApple認証後、GoogleとAppleでUID・会社所属・役割が同一であり、既存給与/請求情報を参照できることを確認する。
- 同意取消、secret失効、未連携Apple、Apple非公開メールを試し、誤った新規所属や権限が付かないことを確認する。
- Release署名済み成果物のcallbackと採用方式のcapabilityを検証し、TestFlight実機で復帰まで確認する。SQL fixtureや単体テストだけでは実機完了としない。

## 公式資料

- https://supabase.com/docs/guides/auth/auth-identity-linking
- https://supabase.com/docs/reference/dart/auth-linkidentity
- https://supabase.com/docs/guides/auth/social-login/auth-apple
- https://developer.apple.com/help/account/capabilities/configure-sign-in-with-apple-for-the-web/
- https://supabase.com/changelog

公式資料の確認では、Manual Linkingはログイン済みアカウント向けで明示設定が必要。OAuthとnativeの両方式があるが、Apple provider設定なしで動作する方式はない。
