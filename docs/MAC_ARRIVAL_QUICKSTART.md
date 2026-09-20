# Mac到着日の最短手順

SKOを自分のiPhoneへ試作インストールするための最短ルート。

## 1. Mac初期準備

1. App StoreからXcodeをインストール
2. Xcodeを一度起動し、追加コンポーネントを完了
3. Xcode > Settings > Accounts でApple Accountへサインイン
4. Flutter SDKをインストール
5. ターミナルで `flutter doctor`

## 2. SKOを取得

```bash
git clone https://github.com/robin4250/sk-works.git
cd sk-works
git checkout main
git pull
```

## 3. Mac診断

```bash
bash tool/check_ios_readiness.sh
```

不足している項目だけ先に解消する。

## 4. Supabase接続値をMacだけに保存

```bash
cp tool/local_supabase_env.example.sh tool/local_supabase_env.sh
```

`tool/local_supabase_env.sh` に以下を設定する。

- SUPABASE_URL
- SUPABASE_PUBLISHABLE_KEY

このファイルはgitignore済みでGitHubには送られない。

## 5. iOSプロジェクト生成

```bash
bash tool/prepare_ios.sh
```

SKO表示名、Face ID、位置情報、カメラ、写真ライブラリの説明文も自動設定される。

## 6. Xcode署名

```bash
open ios/Runner.xcworkspace
```

Xcodeで:

- Runnerを選択
- Signing & Capabilities
- Automatically manage signing: ON
- Team: 自分のApple Account / Personal Team
- Bundle Identifierが重複した場合だけ変更

会社のApple Developer Teamが有効になったら、後でTeamと最終Bundle Identifierを切り替える。

## 7. iPhone接続

1. USBでiPhoneをMacへ接続
2. iPhoneで「このコンピュータを信頼」
3. Developer Modeを要求された場合は有効化
4. MacとiPhoneの両方で接続を許可

## 8. SKOをiPhoneへ起動

```bash
bash tool/run_ios_device.sh
```

スクリプトが実機iPhoneを自動検出し、Supabase接続付きでSKOを起動する。

複数端末がある場合:

```bash
flutter devices
bash tool/run_ios_device.sh <DEVICE_ID>
```

## 9. 最初に確認する順番

1. 電話番号ID
2. 本パスワード2回
3. SMS承認コード
4. 第2パスワード2回
5. Face ID
6. 本人・会社・振込先
7. ホーム
8. 出勤・退勤
9. 出勤表
10. 日報＋責任者サイン
11. チャット
12. 請求書
13. 管理者用現場データ
14. 権限設定

詳細は `docs/IPHONE_ACCEPTANCE_TEST.md` に従う。

## Mac到着前に確認済み

- Flutter analyze: 成功
- Flutter tests: 成功
- Android debug build: 成功
- macOS GitHub runnerでiOSプロジェクト生成: 成功
- iOS権限説明チェック: 成功
- iOS debug build --no-codesign: 成功
- Supabase最新DBマイグレーション: 適用済み
- 必要な非公開Storage buckets: 作成済み

残る実機固有項目はApple署名、iPhone接続、Face ID/GPS/カメラ/SMSなど実端末での確認。
