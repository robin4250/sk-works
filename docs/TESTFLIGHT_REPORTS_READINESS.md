# 帳票Release確認から社内TestFlightへの移行

2026-10-08時点のリポジトリ監査。Appleアカウントへの接続、署名、IPA生成、
アップロード、テスターへの通知はこの監査で実行していない。

## 先に完了する実機確認

最新mainの同一コミットでFlutter CI・iOS CI・Secret Scanを成功させ、
正式採用の請求書v8・給与明細v4とのPDF比較結果を記録する。
`tool/device_day.sh` はReleaseを生成し、
`build/ios/iphoneos/Runner.app` のBundle IDが `com.skworks.skWorks` であることを
確認して既存アプリへ上書きする。ソースバックアップとiPhoneバックアップは
別物であり、端末バックアップの手順は `RELEASE_SOURCE_BACKUP.md` を参照する。

実機で請求書・給与明細・支払証明書を開き、会社名・角印・金額・振込先、
承認済み担当者だけの印影、印影日付を確認する。同じPDFのプレビュー・共有・
印刷を確認し、プリンターを使った印刷結果も記録する。これらはCIだけでは
完了扱いにできない。

## 既存の配布準備と残る確認

- `pubspec.yaml` は `0.2.0+3`。App Store Connectの最新ビルド番号は未確認。
  次回番号は既存のアップロード番号と重複しない値にする。
- `tool/testflight_candidate.sh` は最新mainからApp Store配布用Release IPAを生成し、
  archive内のBundle ID・version・buildを検証する。成果物は
  `build/ios/archive/Runner.xcarchive` と `build/ios/ipa/*.ipa`。
- `tool/testflight_preflight.sh` はFlutter 3.47.5、署名Team設定、署名証明書、
  Release設定を検査する。ただしApple Development証明書の検出だけで
  App Store配布権限が成立したとは判断できない。Xcode 27.0も別途確認する。
- 現在のApple Developer Program会社登録の有効化状態、App Store Connectの
  アプリ登録・権限、配布署名・プロファイルは未確認。

Personal Teamでの自身の端末への開発用署名と、TestFlight配布は別工程。
TestFlightにはApple Developer Programの配布資格が必要であり、会社登録が
保留中なら完了を確認してから配布へ進む。現時点のTeamを推測して切り替えたり、
Bundle IDを変更したりしない。

実機確認とApple側の配布条件が整った後、候補IPAを作成・確認してから
`tool/testflight_upload.sh` またはXcode Organizerでアップロードする。
`tool/testflight_finish.sh` は条件が揃うと自動アップロードするため、候補作成だけの
段階では実行しない。App Store Connectの処理完了後に社内テスターから試験を始める。

Apple公式の区別：
[Developer account overview](https://developer.apple.com/help/account/basics/about-your-developer-account/)、
[Choosing a Membership](https://developer.apple.com/support/compare-memberships/)。
