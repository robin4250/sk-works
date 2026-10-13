# SKO 掲載文・審査案内の下書き

作成日：2026-10-08。App Store Connectへ未登録・未提出。
公開候補を社内試験した後、画面と説明を照合して使用する。
公開条件と未完了事項は [APP_STORE_RELEASE_READINESS.md](APP_STORE_RELEASE_READINESS.md) を参照。
連絡先、サポートURL、プライバシーポリシーURL、審査アカウント、配布日は未確定。
ここに資格情報や仮のURLを記載しない。

## 日本語の掲載文案

**アプリ名案：** SKO

**サブタイトル案：** 会社・社員・勤怠・帳票をまとめて管理

**説明文案：**

SKOは、会社の情報、社員の情報、日々の勤務報告と業務帳票をまとめて扱うアプリです。
管理者と社員がそれぞれの権限で登録データを利用できます。

会社データと社員データを登録し、現場を選んで出勤・退勤を報告できます。
出勤表で勤務実績を確認し、日報や資格・提出書類を管理できます。

請求書、給与明細、支払証明書はPDFでプレビューし、印刷・共有できます。
登録した会社名を使った会社印や、実際に確認した担当者の確認印を帳票に反映します。

給与に関する情報は設定された権限に応じて取り扱います。
社員ごとの給与設定や勤務区分の登録値を確認しながら、帳票を作成できます。
給与計算の利用前には、会社の規定と登録設定を確認してください。

GPS自動出勤を利用する場合は、本人が機能を有効にし、必要な位置情報の利用を許可します。
手動で勤務を登録することもできます。

利用にはSKOのアカウントと所属会社の登録・権限設定が必要です。

**キーワード候補：** 勤怠、出勤表、日報、社員、現場、請求書、給与明細、支払証明書

キーワードの採否・文字数・カテゴリは登録時に確認する。完成していない機能や、
日本国外の給与計算への対応を掲載文へ追加しない。

## English listing draft

**Proposed app name:** SKO

**Proposed subtitle:** Company and work management

**Description draft:**

SKO brings company information, employee records, work reports, and business documents together.
Administrators and employees use registered information according to their assigned permissions.

Register company and employee information, select a work site, and report clock-in and clock-out.
Review attendance records and manage daily reports, qualifications, and submitted documents.

Preview invoices, payroll statements, and payment certificates as PDFs, then print or share them.
Documents can include a company seal generated from the registered company name and confirmation
stamps for the people who actually confirmed the documents.

Access to payroll information depends on the permissions configured for the company.
Check company rules and registered employee settings before using payroll calculations.

GPS automatic attendance requires the user to enable the feature and grant the necessary location
permission. Work reports can also be entered manually.

An SKO account, company registration, and the appropriate permissions are required.

This is a translation draft. It does not claim that every screen or exported document is available
in English. Check the release candidate before choosing English screenshots or publishing this text.

## 審査操作案内の下書き

App Review Informationへ移す前に、候補版で以下の導線を確認し、実際の画面名へ合わせる。
管理者用・社員用のアクセス方法はApp Store Connectの審査情報へ安全に入力し、GitHubへ
保存しない。審査用の架空会社・社員を用意し、実在会社の給与や銀行口座を見せない。

### 管理者で確認する流れ

1. 指定した審査用アカウントでログインする。追加の認証が必要な場合は、審査用の再現方法を案内する。
2. ホームから会社データを開き、登録会社名・給料日等の会社共通設定を確認する。
3. 社員データを開き、審査用社員の社員番号・所属・職種・入社日を確認する。
4. 現場と出勤表を開き、架空の勤務実績を確認する。
5. 個別給与設定と給与明細を開き、設定値と帳票の金額を確認する。
   給与確認が可能な対象月と、確認者に指定したアカウントをあらかじめ用意する。
6. 請求書を開き、PDFの拡大・縮小、登録取引先の表示、会社印を確認する。
7. 支払証明書を開く。登録済みの下請け会社は出勤がない場合もプレビューできる。
8. PDFを共有する。印刷はプリンターのない審査環境でもプレビューと共有で内容を確認できるようにする。

### 社員で確認する流れ

1. 審査用社員アカウントでログインする。初回QRを利用する場合は、審査員が取得・読み取りできる手順を別途案内する。
2. プロフィールを開き、本人の登録情報を確認する。
3. 現場を選んで手動の出勤・退勤を登録し、本人の出勤表へ戻る。
4. 資格・提出書類を開き、審査用の添付を表示する。
5. 本人の給与明細を開く。他の社員や他社の給与が表示されないことを確認する。
6. ログアウトして再度ログインし、会社と本人の登録状態が保たれることを確認する。

### 審査に添える説明の準備

- GPS自動出勤は本人が有効にした場合に指定条件で使用する。設定場所、停止方法、
  位置情報を許可しない場合の手動勤務登録を案内する。
- 確認印は対象期間・現在の版・担当者の確認状態に依存するため、審査用の確認可能な
  対象月を明記する。印影を見せるために実際の確認日時を改変しない。
- アカウント削除の導線と処理は公開準備文書にある未完了項目。完成・通し確認後に
  実際の手順を審査案内へ追記する。ログアウトを削除の代わりに説明しない。
- 審査期間はバックエンドを稼働させる。審査員へのアクセス方法や問い合わせ窓口は、
  運営側で用意できた実際の値を入力する。

## スクリーンショット撮影順

採用する端末サイズはAppleのその時点の仕様に従う。次の順番で、日本語版の候補を先に撮影する。
英語版は翻訳された画面を確認してから撮影し、日本語の画面を英語版として流用しない。

| 順番 | 画面・操作 | 見せる内容 | 撮影前の確認 |
|---|---|---|---|
| 1 | 管理者ホーム | 会社名、勤務報告、主要な業務への入口 | 架空会社名・架空ユーザー名。通知に実在情報がない |
| 2 | 社員データの個人画面 | 社員番号、所属・職種・入社日 | 架空社員。電話・住所・緊急連絡先も実在情報を使わない |
| 3 | 出勤表 | 現場と勤務実績 | 日付と架空勤務を統一し、操作前後で矛盾しない |
| 4 | 給与明細PDF | 採用レイアウト、金額、確認印 | 架空給与と架空振込先。確認した担当者だけの印影 |
| 5 | 請求書PDF | 取引先、明細、税率・福利厚生費率、会社印 | 架空取引先。計算結果と登録値が一致 |
| 6 | 支払証明書PDF | 下請け会社向け帳票 | 架空会社。未登録口座や出勤なしの状態を隠して完成扱いにしない |

画面に機能が現れている場合だけ説明の見出しを付ける。将来の機能、公開日、
給与計算・法令適合の保証は画像へ記載しない。掲載用画像の実ファイルはまだ生成していない。
