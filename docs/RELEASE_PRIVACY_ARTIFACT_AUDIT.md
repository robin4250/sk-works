# Releaseプライバシー成果物の読み取り監査

この監査は実際にビルドされた `Runner.app` を読み取り、Info.plist、組み込まれたFramework、
`PrivacyInfo.xcprivacy` の内容を標準出力へJSONで出します。ビルド・署名・インストール・
ファイル変更・通信は行いません。MacのPython 3が必要です。

```bash
bash tool/audit_release_privacy_artifact.sh "$PWD/build/ios/iphoneos/Runner.app"
```

Archiveを調べる場合は、対象 `.xcarchive/Products/Applications/Runner.app` の実在パスを渡します。
結果を保存する場合だけ、コマンド末尾に `> /保存先/privacy-artifact-audit.json` を付けてください。

検出対象はBundle ID `com.skworks.skWorks`、設定済みのFace ID・位置情報・背景位置情報・
カメラ・写真の用途説明、背景位置モード、Flutter AOT実行ファイルです。Debugの
`kernel_blob.bin` や明示的な開発フラグ、壊れたplist、必須項目不足は終了コード1になります。

**終了コード0だけでRelease確認済みとは扱いません。** ProfileもAOTを使うため、Releaseの
ビルド/Archiveログを別に照合します。署名Entitlementsの `get-task-allow`、組み込まれたSDKの
署名もMacで確認してください。Info.plist内の同名フラグ確認は署名Entitlementsの代わりにはなりません。

Manifestは格納場所ごとに追跡フラグ、追跡ドメイン、収集データ、required-reason APIの宣言を
そのまま列挙します。Manifestが0件でも不要とは判定しません。実装・SDK・実通信を確認し、
Appleの現行要件に照らして不足を評価してください。このスクリプトは理由コードや収集ラベルを
生成せず、App Store Connectへ何も登録しません。

実機での権限拒否、GPS有効/停止、背景動作、削除導線、プライバシーポリシー公開URLの確認は
[APP_STORE_RELEASE_READINESS.md](APP_STORE_RELEASE_READINESS.md) の残作業です。
帳票や既存アプリのRelease上書き経路は既存リリースゲートを使います。
