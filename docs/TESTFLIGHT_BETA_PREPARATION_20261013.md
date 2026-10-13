# SKO ベータ版｜TestFlight準備（2026-10-13）

この文書は準備の整理です。Apple側の登録完了、配布署名、IPA作成、アップロード、テスター招待・配布を実施した記録ではありません。現行mainのスクリプトを読み取り確認しました。実機とセキュリティ検証を終えるまで配布しません。

## 順番と入口

1. 現在の機能・修正を仕上げ、同じBundle ID `com.skworks.skWorks` の署名付きReleaseを既存iPhoneアプリへ上書きする。既存アプリは削除しない。導入前にソースをバックアップする。
2. 実機で表示・保存・操作を確認し、不具合を修正する。ヘルプ・説明書・パンフレットを現行機能に合わせて「ベータ版」として更新する。
3. その間にTestFlightの候補情報と確認項目を準備する。専用セキュリティ作業は現在の仕上げ・実機確認後に開始し、配布はその検証後とする。
4. Apple Developer登録・配布権限が確認できればTestFlightへ進む。確認待ちで進めない場合は、セキュリティ完了後のWeb版を優先する。Android社内利用者の有無はユーザーが確認し、いなければAndroidテスト配布は後回しとする。

Macでの上書きは [iphone_release_install.md](iphone_release_install.md)、既存の検査入口は [TESTFLIGHT_RELEASE_GATE.md](TESTFLIGHT_RELEASE_GATE.md) を使う。Debug導入・`flutter run` は使わない。ソースバックアップはiPhone内データ・本番DB・添付ファイルのバックアップとは別である。

## 現時点の確認区分

| 項目 | 状態・次に必要な証拠 |
|---|---|
| Bundle ID | 既存の実機導入・候補作成スクリプトは `com.skworks.skWorks` の一致を確認する |
| ローカルReleaseとTestFlight | 実機向け `flutter build ios --release` と、App Store向け `flutter build ipa --release --export-method app-store` は別工程 |
| Apple Developer登録 | 会社登録完了・有効なチーム・App Store Connectアクセスは未確認。過去の「手続き中」を完了扱いにしない |
| 署名 | ローカル実機署名やPersonal Teamでの起動成功だけではTestFlight配布署名を確認したことにならない。今回Personal Team使用を実際に確認した記録もない |
| バージョン・ビルド番号 | 候補作成時に最新pubspecとApp Store Connectの利用済み番号を確認する。未使用番号を推測しない |
| CI | 配布候補の同じcommitでFlutter・iOS・Secret Scanと必要な機能検査の結果を再確認する。以前の別headの成功を流用しない |
| 実機 | インストール実ログ、単体起動、機能別の実操作結果が必要。CIやコマンド提示だけで完了扱いにしない |
| セキュリティ検証 | 現在の仕上げ後の工程。完了するまで配布しない |
| アップロード・配布 | 未実施。アカウント承認・成果物処理完了・対象グループ・テスター招待をそれぞれ記録する |

## 今できる準備

- 候補commit、版番号、実機結果、未解消不具合、CI実行URLを同じ記録にまとめる。
- 「ベータ版」のテスター向け案内を準備する。対象機能、既知の制約、再現手順、報告方法を明記し、未確認機能を完成と書かない。
- テスター候補と必要なアクセス方式を整理する。社員だから自動的にAppleの「内部テスター」になるわけではない。内部テスターは対象アプリへのアクセスを持つApp Store Connectユーザーである。不要な管理権限を配る前提にしない。
- プライバシー・掲載・審査情報の未確認項目は [APP_STORE_RELEASE_READINESS.md](APP_STORE_RELEASE_READINESS.md) に集約し、同じ棚卸しを重複作成しない。
- Apple認証情報、API秘密鍵、パスワードはGit・説明書・ログ・クリップボードへ出さない。新しい契約・請求先登録やアカウント操作はこの準備で行わない。

## 既存スクリプトを使う時の境界

| スクリプト | 実際の処理・注意 |
|---|---|
| `tool/device_day.sh` / `tool/run_ios_device.sh` | ソース保存・検査・iOS生成・実機署名を経てReleaseを既存アプリへ上書きする。TestFlightアップロードとは別 |
| `tool/testflight_preflight.sh` | Macの事前検査。署名identity判定はApple DevelopmentまたはApple Distributionの存在を認めるため、成功だけで配布署名・Apple登録・App Store Connect権限の完了とは判定できない |
| `tool/testflight_candidate.sh` | iOS生成設定を更新し、事前検査後にApp Store向けIPAを作る。今回未実行。main取得後の参照鮮度、未保存差分、バックアップを確認してから使う |
| `tool/testflight_finish.sh` | 候補作成に続き、API設定が存在するとアップロードへ自動進行する。準備だけの段階では実行しない |
| `tool/testflight_upload.sh` | App Store Connectへ送信する処理。準備段階では実行しない |

候補・事前検査・アップロードの各スクリプトは `git fetch origin main` 後に `origin/main` とHEADを比較する。狭いremote fetch設定ではtracking refが古い場合があるため、最新取得結果とHEADの一致を別途確認する。この文書ではスクリプトを変更していない。

Apple側の自動配布設定も未確認である。アップロードだけでも自動配布設定によって配信へつながり得るため、配布開始条件を満たす前にはアップロードしない。

## 配布へ進む時に残す記録

既存ゲートを通過した同じ候補について、Apple登録・権限、配布署名、実機確認、セキュリティ検証、バックアップ範囲、版番号、IPAの識別情報、アップロード処理完了、対象テスターと招待結果を個別に記録する。最初は適切な社内テスター向けの小さい範囲から始め、受信・導入・起動の実結果を確認する。

## 確認したApple一次資料

- [TestFlightの概要](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)
- [内部テスターの追加](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers)
- [ベータテストと公開の配布](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases)
- [App Store Connect配布方法](https://help.apple.com/xcode/mac/current/en.lproj/dev31de635e5.html)

これらは配布方法の根拠であり、SKOのApple登録・署名・配布完了の証拠ではない。
