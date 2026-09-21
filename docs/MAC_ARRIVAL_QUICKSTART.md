# Mac到着日の最短手順

SKOを自分のiPhoneへ試作インストールするための最短ルート。

## 1. Mac初期準備

1. App StoreからXcodeをインストール
2. Xcodeを一度起動し、追加コンポーネントを完了
3. Xcode > Settings > Accounts でApple Accountへサインイン
4. Flutter SDKをインストール

## 2. SKOを取得

```bash
git clone https://github.com/robin4250/sk-works.git
cd sk-works
git checkout main
git pull
```

## 3. 最短: 1コマンドで実機起動まで進める

MacとiPhoneが手元に来たら、まず次を実行する。

```bash
bash tool/device_day.sh
```

このコマンドが、Mac初回準備 → Mac/iPhone非依存release gate → 実機当日の一括プリフライト → SKO実機起動まで順番に進める。`tool/local_supabase_env.sh` が無い場合はテンプレート作成、iOSプロジェクトが無ければ生成まで自動で進める。
Apple Account / Personal Team / USB信頼 / Developer Modeなど、人が操作する必要がある箇所で止まった場合は画面の案内を解消し、同じコマンドをもう一度実行する。

問題調査が必要な場合:

```bash
bash tool/collect_ios_diagnostics.sh
```

Mac/iPhoneなしでも先にrelease gateだけ確認したい場合:

```bash
bash tool/pre_device_release_gate.sh
```

このrelease gateは、依存固定/lockfile、秘密情報、migration整合、shell構文、Flutter analyze/testをまとめて検査する。

以下は個別に実行したい場合の詳細手順。

## 4. Mac初回セットアップ診断

```bash
bash tool/mac_first_run.sh
```

この1コマンドで次をまとめて確認する。

- Xcode / 初回セットアップ
- Git
- Flutter
- Python 3
- CocoaPods
- Supabaseローカル設定
- iOSプロジェクト生成

`tool/local_supabase_env.sh` が無い場合は、公開クライアント設定済みテンプレートから自動作成してその場で読み込む。

## 5. Supabase接続値

SK WORKSの公開クライアント用 `SUPABASE_URL` と `SUPABASE_PUBLISHABLE_KEY` はテンプレートへ設定済み。

`bash tool/device_day.sh` または `bash tool/mac_first_run.sh` の初回実行時に `tool/local_supabase_env.sh` を自動作成して読み込むため、通常は手入力不要。

このローカルファイルはgitignore済み。service_roleやsecretキーはアプリ側へ入れない。

## 6. iOSプロジェクト生成

`mac_first_run.sh` が必要条件を満たしていれば自動生成する。
手動で準備をやり直す場合:

```bash
bash tool/prepare_ios.sh
```

既にiOSプロジェクトがある場合は再生成せず再利用するため、Xcodeで設定済みのSigning Teamを保持したまま権限説明・Bundle Identifier等を更新する。

SKO表示名、Face ID、位置情報、カメラ、写真ライブラリの説明文に加えて、Personal Team向けのBundle Identifier `com.robin4250.sko` も自動設定される。

もしApple側でBundle Identifierが重複すると表示された場合だけ、次のように任意の固有IDへ変更して再実行する。

```bash
SKO_IOS_BUNDLE_ID=com.robin4250.sko.dev bash tool/prepare_ios.sh
```

## 7. 実機当日の一括プリフライト

```bash
bash tool/device_day_preflight.sh
```

この1コマンドで、CI基準のFlutter 3.47.5、Supabase Auth/REST到達、署名、Bundle Identifier、Signing Team、実機iPhone認識までまとめて確認する。

必要に応じて個別診断も利用できる。

```bash
bash tool/ios_install_assistant.sh
```


この1コマンドで、必須ツール、Supabase設定、iOSプロジェクト、Bundle Identifier、Signing Team、実機iPhone接続をまとめて確認する。

- `✓`: 完了
- `△`: 次に行う実機固有作業
- `✗`: 実機起動前に必須の不足項目

Signing Teamが未設定なら、表示された案内どおりXcodeを開く。

## 8. Xcode署名

```bash
open ios/Runner.xcworkspace
```

Xcodeで:

- Runnerを選択
- Signing & Capabilities
- Automatically manage signing: ON
- Team: 自分のApple Account / Personal Team
- Bundle Identifierは通常 `com.robin4250.sko`
- 重複エラー時のみ、上記 `SKO_IOS_BUNDLE_ID` で変更

会社のApple Developer Teamが有効になったら、後でTeamと最終Bundle Identifierを切り替える。

## 9. iPhone接続

1. USBでiPhoneをMacへ接続
2. iPhoneで「このコンピュータを信頼」
3. Developer Modeを要求された場合は有効化
4. MacとiPhoneの両方で接続を許可
5. もう一度 `bash tool/ios_install_assistant.sh` を実行

すべて揃うと「iPhone実機起動の準備が整っています」と表示される。

## 10. SKOをiPhoneへ起動

```bash
bash tool/run_ios_device.sh
```

スクリプトが実機起動前チェックを再実行し、問題がなければ実機iPhoneを自動検出してSupabase接続付きでSKOを起動する。

複数端末がある場合:

```bash
flutter devices
bash tool/run_ios_device.sh <DEVICE_ID>
```

## 11. 最初に確認する順番

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

- Flutter 3.47.5 / Dart 3.13.4へCI固定: 成功
- Flutter analyze: 成功
- Flutter tests: 成功
- Android debug build: 成功
- macOS GitHub runnerでiOSプロジェクト生成: 成功
- iOS権限説明チェック: 成功
- Personal Team用Bundle Identifier自動設定: 成功
- iOS debug build --no-codesign: 成功
- iOS補助スクリプトの構文チェック: CI対象
- Supabase最新DBマイグレーション: 適用済み
- 必要な非公開Storage buckets: 作成済み
- 電話番号＋パスワード登録はSMSチャネルを明示
- 070/080/090形式の日本携帯番号正規化テスト: 成功

残る実機固有項目はApple署名、iPhone接続、Face ID/GPS/カメラ/SMSなど実端末での確認。
