# SKO iPhone実機テスト準備

Mac到着後、まずこの順番で進める。

## 1. Mac側

1. XcodeをApp Storeからインストール。
2. Xcodeを一度起動し、追加コンポーネントのインストールを完了。
3. Xcode > Settings > Accounts でApple Accountへサインイン。
4. Flutter SDKを用意し、ターミナルで `flutter doctor` を実行。
5. GitHubから `robin4250/sk-works` のmainを取得。

## 2. iOSプロジェクト生成

リポジトリ直下で:

```bash
bash tool/prepare_ios.sh
```

このスクリプトは以下を行う。

- iOSプロジェクト生成
- Flutter依存関係取得
- Face ID説明文追加
- 位置情報説明文追加
- カメラ説明文追加
- 写真ライブラリ説明文追加

## 3. Xcode署名

```bash
open ios/Runner.xcworkspace
```

Runner > Signing & Capabilities:

- Automatically manage signing: ON
- Team: 自分のApple Account / Personal Team
- Bundle Identifier: 他と重複しない値
- Deployment targetは現在のiPhone OSに対応する値

Apple Developer Program会社登録がまだ処理中でも、Personal Teamで実機テスト可能な範囲を先に使う。

## 4. iPhone

1. MacとiPhoneをUSB接続。
2. 「このコンピュータを信頼」を許可。
3. Xcode上部の実行先で自分のiPhoneを選択。
4. 初回のみiPhone側でDeveloper Modeを求められた場合は有効化。
5. XcodeのRunでSKOをインストール。

## 5. SKO実機確認の優先順

1. 初回登録
   - 電話番号ID
   - 本パスワード2回
   - SMS承認コード
   - 第2パスワード2回
   - Face ID
2. 本人・会社・振込先登録
3. 一般ユーザーホーム
4. 管理者ホーム
5. 出勤・退勤
   - 手動
   - 位置情報
   - 位置情報＋写真
6. 出勤表
   - 週表示
   - 月間カレンダー
7. 日報
   - 朝の出勤メンバー反映
   - 残業/早出/手当
   - 責任者サイン
8. チャット
   - すべて
   - 現場
   - 個別
   - 協力会社（権限時）
   - 写真/ファイル
9. 請求書・管理者用現場データ
   - 第2認証
10. 通知・権限設定

## 6. Supabaseで実機前に必要

電話番号登録でSMSを実際に受け取るには、Supabase AuthenticationでPhoneを有効化し、SMSプロバイダ設定が必要。

マイグレーションはmainの `supabase/migrations` を最新まで適用してから実機テストする。

## 7. iOSでMac到着後に最終確認する項目

- Face ID / Touch ID
- SMS受信
- GPS
- カメラ
- 写真選択
- ファイル選択
- 印刷 / 共有 / メール送信
- 実機画面サイズでのレイアウト
- キーボード表示時の画面崩れ


## 8. Supabase接続付きでiPhoneへ起動

SKOはSupabase接続値をソースコードに埋め込まず、Dart defineで受け取る。

ターミナルから実機起動する場合:

```bash
flutter run \
  --dart-define=SUPABASE_URL="<Supabase Project URL>" \
  --dart-define=SUPABASE_PUBLISHABLE_KEY="<Publishable Key>"
```

XcodeだけでRunする場合は、Flutter側のDart defineをビルド設定へ渡す必要があるため、初回は上記 `flutter run` を使う方が簡単。

秘密鍵/service_roleキーは絶対にiPhoneアプリへ入れない。使用するのはPublishable Keyのみ。
