# SKO iPhone実機テスト準備

現在の最短ルートは、Mac到着後に補助スクリプトを順番に実行する方法。

## 1. Mac初回準備

1. App StoreからXcodeをインストール
2. Xcodeを一度起動して追加コンポーネントを完了
3. Xcode > Settings > Accounts でApple Accountへサインイン
4. GitHubからmainを取得

リポジトリ直下で:

```bash
bash tool/mac_first_run.sh
```

このスクリプトがXcode、Flutter、Python 3、CocoaPods、Git、Supabaseローカル設定、iOSプロジェクト生成をまとめて確認する。

## 2. Supabase接続値

`tool/local_supabase_env.sh` に以下だけを設定する。

- SUPABASE_URL
- SUPABASE_PUBLISHABLE_KEY

秘密鍵やservice_roleキーはiPhoneアプリへ入れない。

## 3. 実機インストール診断

```bash
bash tool/ios_install_assistant.sh
```

現在は次まで確認する。

- Xcode Command Line Tools
- XcodeのDeveloper Directory
- Apple Development署名証明書
- Flutter / CocoaPods / Python 3 / Git
- Supabase URL / Publishable Key
- iOSプロジェクト
- Bundle Identifier
- Signing Team
- Flutterから見た実機iPhone
- 必要に応じてXcodeのdevice control状態

## 4. Xcode署名

診断でSigning Teamまたは署名証明書が未設定なら:

```bash
open ios/Runner.xcworkspace
```

Runner > Signing & Capabilities:

- Automatically manage signing: ON
- Team: Apple Account / Personal Team
- Bundle Identifier: 通常は `com.robin4250.sko`

会社のApple Developer Program登録完了前でも、まずPersonal Teamで自分のiPhoneへの動作確認を優先する。

## 5. iPhone接続

1. USBでiPhoneをMacへ接続
2. iPhoneで「このコンピュータを信頼」
3. Developer Modeを要求された場合は有効化
4. XcodeでもiPhoneが見えることを確認
5. 再度 `bash tool/ios_install_assistant.sh`

すべて揃うと「iPhone実機起動の準備が整っています」と表示される。

## 6. SKOを実機起動

```bash
bash tool/run_ios_device.sh
```

このスクリプトは実機起動前診断を再実行し、Supabase接続値をDart defineで渡してiPhone上でSKOを起動する。

## 7. 実機確認の優先順

1. 電話番号ID / 本パスワード
2. SMS承認
3. 第2パスワード
4. Face ID
5. 本人・会社・振込先
6. 一般 / 管理者ホーム
7. 出勤・退勤
8. 出勤表
9. 日報・責任者サイン
10. チャット
11. 請求書・管理者用現場データ
12. 通知・サブ管理者権限

詳細チェックは `docs/IPHONE_ACCEPTANCE_TEST.md` を使用する。

## 8. Mac到着前にCIで確認済み

- Flutter analyze
- Flutter tests
- Android debug build
- macOS runnerでiOSプロジェクト生成
- Face ID / 位置情報 / カメラ / 写真ライブラリ説明文
- Personal Team向けBundle Identifier
- iOS debug unsigned build
- iOS補助スクリプトのshell構文

残るのはApple Account / Personal Team署名、実iPhone接続、Face ID、SMS、GPS、カメラ等の実端末依存確認。
