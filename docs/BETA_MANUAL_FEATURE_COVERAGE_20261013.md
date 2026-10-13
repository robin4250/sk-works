# SKO ベータ版・説明書と機能の照合

改訂日：2026-10-13。現在の `MenuHelpCatalog.items` の39項目を、役割別説明書・パンフレットの章と実装ソースに対応させています。機械可読の対応は [manual_feature_coverage.json](manual_feature_coverage.json)。項目を追加したときは目次・章・対応表・画面の「？」を合わせて更新します。

既存の章の順序を保持し、新しい説明は後ろへ追加します。一般23章、サブ管理者39章、管理者51章、パンフレット51章です。これは章数であり固定のページ数ではありません。各機能の文章量に合わせて自動改ページし、全文PDFと機能別PDFを同じ「使い方・説明書」の入口から開きます。PDFは日本語版です。

## 主な対応と読み分け

| 分野 | 説明する内容 | 主な実装参照 |
| --- | --- | --- |
| 初期準備・本人・社員 | 初回ログイン、本登録、社員情報、役割、個人情報変更承認 | `profile_page.dart`、`employee_personnel_detail_page.dart`、`worker_personnel_change_approvals_page.dart` |
| 勤怠・日報・ルート | 出退勤、週/月出勤表、現場/月日報、実写真分類、現場到着/移動、会社別数量申請/承認 | `worker_attendance_sheet_page.dart`、`daily_report_month_page.dart`、`route_journey_capture_page.dart`、`route_customer_day_quantity_page.dart` |
| チャット・ノート・アルバム | タブ、最新本文、未読、写真アイコン、ノート本文/ピン、アルバム写真 | `chat_cloud_page.dart`、`notes_cloud_page.dart`、`albums_cloud_page.dart` |
| 資格・書類 | 本人/社員の共通カード、実添付、資格表裏、会社提出書類の写真管理 | `own_document_registration_page.dart`、`own_qualification_registration_page.dart`、`company_submitted_documents_page.dart` |
| 会社・契約・受信 | 取引/協力会社の登録と契約、使用中会社の削除制約、受信/保存/再転送 | `trade_company_page.dart`、`company_delivery_inbox_page.dart` |
| 経費 | 本人申請、任意領収書、保存再確認、承認/却下、負担先/精算方法 | `expense_personal_page.dart`、`expense_review_detail_page.dart` |
| 帳票・設定 | 通常請求書、支払証明書設定、月次と現場別合意、保存済み給与設定/調整 | `invoice_cloud_page.dart`、`payment_certificates_page.dart`、`individual_payroll_settings_page.dart` |
| ホーム・設定 | 天気、交通、表示/並び順、外観、通知音、動かせる「？」、機能別目次 | `weather_forecast_card.dart`、`home_appearance.dart`、`settings_page.dart`、`manual_library_page.dart` |
| LINE | 読取専用トーク/当日候補と、月次表の照合/署名申請、履歴単価からの請求下書き | `today_line_attendance_page.dart`、`line_import_page.dart`、`line_historical_invoice_bridge_page.dart` |

「本日のLINE出勤候補」は保存しない読取専用画面です。正式な勤怠申請は別のLINE出勤表で確認・照合・保存・署名を通します。通常の取込請求と、過去単価を明示するマスター履歴請求を混同しません。公式参加グループ一覧と通常グループへの追加はPR #978の確定ソースと照合しています。この説明書をmainへ反映する前に、#978のmain反映後のコードを取り込み、組み合わせたCIを確認します。

PDF検査は全章本文・手順・補足の抽出、A4印刷範囲、解決済み目次/戻りリンク、長い手順と段落の複数ページ化を確認します。長い段落ではページ間のヘッダー/フッターだけを除いて本文を比較し、補足の末尾まで確認します。PNGへの描画確認と、iPhoneでの実表示・操作は別に記録します。

この照合は、実機、実LINE投稿、実履歴の請求書、カメラ保存、承認/発行の一連の検証が完了したことを意味しません。給与機能は現在mainの保存済み画面を説明するだけで、Mac担当の未反映作業を説明に先取りしません。TestFlightの準備と配布開始の条件は [TESTFLIGHT_BETA_PREPARATION_20261013.md](TESTFLIGHT_BETA_PREPARATION_20261013.md)。
