# SKO ベータ版・説明書と機能の照合

## 2026-10-14 更新：LINEの配布対象と説明書の未完了条件

TestFlight・無料公開ではLINEトークを一般利用者へ開放しない。下記対応表のLINE機能は実装参照の整理であり、一般テスターが利用できるという案内ではない。一般向けの目次・手順・パンフレットは、実際の制限を確認してLINEを対象外として読み分ける更新が必要であり、現時点で完了扱いにしない。

server/UIの一般非開放制御は #1034・#1035 で実装・隔離検査を終えてmainへ反映した。本番は `general_enabled=true` の現状維持で、一般利用を停止する切替は未実施。ホーム・メニュー、共有トーク、通知・直接遷移とサーバー読書権限まで配布前に非開放を検証することが、[残る配布条件](TESTFLIGHT_RELEASE_GATE.md)である。実Realtime、既取得URL、外部送信in-flightと実機は未確認であり、説明書やCIだけで封印完了とは扱わない。詳細は [LINE一般非開放の現況](LINE_GENERAL_RELEASE_PREPARATION_20261014.md) を参照する。

マスターの自社請求整理は継続する。2024年1月からの実データを月別表で照合・修正し、過去単価から既存採用様式の請求書を作成・確認した後、形を整えて一時封印する。封印がTestFlight前か後かは請求書確認次第で判断し、先に封印しない。保存データは保持する。一般非開放の実装と、本番一般停止・封印の実施は区別する。この文書更新で設定・データ・連携状態を変更しない。

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
