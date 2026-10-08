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

## 給与・勤怠連携の社内試験

計算の検証は隔離DBの架空データで行い、本番社員の給与設定を試験用に変更しない。実機では以下の流れを試験会社の登録データで確認する。

| 操作・組み合わせ | 確認する結果 |
|---|---|
| 日報を署名して出勤登録、同じ日報を再署名 | 同じ勤怠を更新し、金額・人工を重複加算しない |
| 同じ日に2現場を各0.5人工 | 出勤した日付は1日、人工合計は1、登録単価で計算 |
| 休日・休日夜勤と残業・早出 | 選んだ勤務区分と個別給与設定の単価を使用 |
| 20時出勤・翌5時退勤、月末・年末 | 出勤表の勤務日に翌朝退勤を表示 |
| 有給申請後、同日に出勤を登録して承認 | 出勤・有給を重複させず、給与明細と出勤表のカウントが一致 |
| 個別給与設定を保存して給与明細を開き直す | 保存済み設定を使った再計算結果を表示 |
| 金額が変わらない再保存 | 確認状態・実際の確認日時を不要に変更しない |
| 金額変更後の再確認、確認取り消し | 現在の版への印影を表示し、一覧へ戻ると状態を再取得 |
| 出勤なし・有給のみの月給社員 | 登録済み固定月給を維持し、重複加算しない |
| PDFプレビューから共有・印刷 | 同じPDFデータ・金額・確認印を使用 |

日給・時給社員の有給支給額、通常勤務の夜間時間加算、月給社員の夜勤・休日の日額が追加支給か差額支給かは、現在の登録設定に判定規則がない。これらは金額の一致確認が完了した扱いにせず、会社規定を決めて登録元を統一する。日報に紐づかないGPS夜勤の翌朝退勤も未完了として記録する。
