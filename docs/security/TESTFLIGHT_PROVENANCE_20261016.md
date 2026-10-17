# TestFlight候補のソース・署名・IPA照合

このゲートは候補の取り違えを防ぐ実装です。セキュリティ配布承認、LINEの本番制限、実JWTの他社拒否、実機合格を自動的に認定しません。既存の `docs/TESTFLIGHT_RELEASE_GATE.md` を満たすまで配布しません。

## 実行する検査

- 候補作成前・ビルド開始前・検証後・アップロード前に、main、origin/mainとの一致、追跡/未追跡の未保存変更なしを照合します。変更を削除・退避・resetする処理はありません。
- GitHub CLIの既存認証でexact main SHAのpushまたは手動実行CIを照合し、Flutter CI / iOS CI / Secret Scan / TestFlight provenanceの最新実行が成功していなければ停止します。CI API失敗・結果不足・100件超過も停止します。トークンやログを取得・表示しません。
- 成功した `flutter build ipa --release --export-method app-store` の開始記録より新しいIPAを1個に限定します。複数の既存IPAは自動削除しません。必要なら利用者が保管してから再試行します。
- IPAを一時領域に展開し、危険なZIPパス・symlink・過大な展開を拒否します。Bundle ID、version/build、AOT、Debug kernel不在、広範ATS無効化なしを確認します。
- macOS codesignのstrict/deep検証、署名entitlements、配布profileのteam/application identifier/get-task-allow=false、App Store/TestFlight区分、有効期限、profile内署名証明書との一致を検証します。
- 候補manifestはcommit/main/Releaseの構築記録、正確なIPA絶対パス、SHA256、version/build、署名識別、CI run IDを保持します。アップロード時はglob選択せず、このIPAの署名とSHAを再検証します。
- 署名検査の前後および最終照合でSHA256の不変を検査します。アップロードは所有者のみがアクセスできる一時ディレクトリの読み取り専用コピーを作り、そのコピーを署名・SHA照合して同じパスをaltoolへ渡します。終了時はコピーだけ削除し、元IPAを保持します。

`build/ios/sko-testflight-provenance.json` はローカルの構築記録であり、署名された第三者証明ではありません。ローカルのコード実行権限を持つ攻撃者に対する改竄耐性を保証しません。Releaseは実行した構築コマンドとソースの同一性で確認し、AOTだけではProfileと区別しません。

commitとIPAを暗号学的に結び付けた埋め込み証明はありません。clean SHA・構築開始時刻・通常の固定Releaseビルド経路・検査したファイルのhashによる取り違え防止です。App.frameworkの存在とDebug kernel不在だけで任意の偽装バイナリをReleaseと認証しません。codesign/profile検査はMacのローカル信頼ストアとツールに依存し、Apple側での受付・証明書失効状態・サービス全体の安全性の確認を代替しません。所有者やrootが権限を戻してコピーやツールを書き換えるホスト侵害を、この一時コピーで防げるとは扱いません。

候補作成には既存の `bash tool/testflight_candidate.sh`、APIアップロードには `bash tool/testflight_upload.sh` を使用します。追加要件はPython 3と認証済みGitHub CLIです。APIキー未設定時にOrganizerの別Archiveを自動で開く経路は停止し、検証済みIPAのTransporter利用を案内します。Transporterで別ファイルを選ぶ操作までこのスクリプトが制御することはできません。

専用provenance検査は変更パスに関係なく全main pushで実行します。既存Flutter/iOS CIのpushパス条件は維持し、exact mainで必要な実行がない場合だけ、担当者が次の手動実行を開始できます。このPRで実行要求は送っていません。実行後は成功を待ち、mainが進んでいたら新しいSHAで再確認します。古いSHAや別ブランチの成功は採用しません。

```bash
gh workflow run flutter-ci.yml --ref main
gh workflow run ios-ci.yml --ref main
```

## 検査の範囲

`python3 tool/test_testflight_provenance.py` は実ZIP/合成plist・擬似署名ツール・一時Gitの実行試験です。Macの実署名証明書・Apple側のprofile・アーカイブ・アップロード・本番認証・データ・通知は使用しません。Linuxで署名確認を省略するオプションはありません。

配布前には実Macで署名済みIPAの通過と、改変/古い候補/未保存変更の停止を確認します。プライバシーmanifest、署名済みentitlements、実SDK、権限拒否・ログアウト・actor変更・他社拒否、LINE非公開の確認は引き続き必要です。ゲートを通すための本番RLS弱化やフラグ変更は行いません。

## 2026-10-17: 監査SHAとローカル構築文脈の固定

`SKO_AUDITED_SHA` に配布審査した40桁SHAを明示してください。start/source/create/validate/stageはすべてHEAD・origin/main・この値の一致を必須とし、未指定やmain前進では停止します。これは自己申告の審査対象固定であり、配布安全承認自体を自動発行しません。最終統合SHAは未確定のため、今はビルド・uploadを実行しません。

manifest schema 2 は構築開始時と検査時の Flutter 3.47.5/revision/engine/Dart と Xcode version/build、および厳格allowlistのnative source digestを照合します。対象は ios/Runner/Info.plist、ios/Runner.xcodeproj/project.pbxproj、共有Runner.xcscheme、Runner直下の*.entitlementsのみ。symlinkのファイル/祖先は拒否します。秘密鍵・env・Generated.xcconfig・資格情報・ログをhash対象にせず、値を保存しません。独自追加xcconfig等をこれで網羅したとは扱いません。

Releaseコマンドは専用Masterフラグfalseを明示します。構築後のGenerated.xcconfigはローカル比較だけに使い、固定プロジェクトの公開URL・publishable key非空・Masterフラグfalseの3定義だけを許可します。定義値や鍵のhashは保存しません。これは固定コマンド/生成設定の一致であり、IPA内から全Dart定数を逆検証した証明ではありません。

検査したIPAのcompiled Google callback scheme・FlutterDeepLinkingEnabled=falseを必須とし、署名が返したentitlements全体とembedded.mobileprovisionのdigestをmanifestへ追加します。profile/entitlements本文や認証情報を保存せず、同一IPAの再検査で比較します。Appleログインを有効と認定するものではなく、Apple capabilityが必要な候補は別の実機/サーバー設定検査が必要です。

schema 1の旧manifestや旧markerは互換通過させません。元IPAを削除せず保管し、新しい承認SHAと固定Release経路で新候補を作る必要があります。本番RLS・LINE非公開・実機認証の安全条件は引き続き別途必須です。
