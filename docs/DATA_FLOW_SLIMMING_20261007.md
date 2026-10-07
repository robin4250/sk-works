# SKO データフロー / スリム化監査

## 原則
1. 勤務実績は attendance_entries を一次データとする。
2. 社員へ支払う単価は worker_payroll_settings（個別給与設定）を正とする。
3. 顧客へ請求する単価は site_financial_settings.billing_* / 取引先契約を正とする。
4. 帳票は一次データと設定から生成された派生結果を表示し、同じ実績を再入力しない。
5. 旧互換列は参照ゼロを確認するまで削除しない。

## 現在確認できた経路

### 勤務実績
attendance_entries
- base_man_days
- overtime_hours
- early_hours
- work_category
- allowance_names

この実績を給与・請求書・支払証明書が参照する。

### 給与
attendance_entries
→ worker_payroll_settings
→ private.refresh_automatic_payroll
→ payroll_statements
→ 給料明細

正:
- 日給 / 時給 / 月給
- 月固定給
- 計算用1日基本ベース
- 残業・早出・夜勤・休日系計算式
- 個別手当・控除

### 請求書
attendance_entries
→ site_financial_settings.billing_* または trade_company_contracts
→ private.refresh_automatic_invoice
→ invoices.snapshot
→ InvoiceCalculationResult
→ InvoicePdfService.buildPdf
→ 画面 / 印刷 / 共有

請求生成SQLは billing_* を参照し、site_financial_settings.worker_* は請求金額に使用しない。

### 支払証明書
attendance_entries
→ partner_payment_settings
→ payment_certificate_detail_rows
→ 支払証明書

協力会社への支払単価なので、社員給与・顧客請求とは別用途として維持する。

## 重複・整理対象

| 場所 | 項目 | 判定 | 方針 |
|---|---|---|---|
| 管理者用現場データ | worker_daily_rate_yen / worker_rate_formula / worker_rate_overrides 等 | 重複・旧互換 | UIから非表示。値は当面保持 |
| 管理者用現場データ | billing_* | 使用中 | 請求設定として維持 |
| 個別給与設定 | worker_payroll_settings | 使用中・給与の正 | 給与設定をここへ集約 |
| 会社単価・手当設定 | overtime/early/night/holiday | 旧初期値・要監査 | 新規給与の正にしない。残存参照確認後整理 |
| 協力会社支払設定 | partner_payment_settings | 使用中 | 支払証明書専用として維持 |
| attendance_entries | 残業/早出/勤務区分 | 使用中・実績の正 | 1回だけ入力 |

## 画面の役割
- 出勤表 / 勤務修正: 実績
- 個別給与設定: 社員へ支払う金額のルール
- 管理者用現場データ: 顧客へ請求する金額のルール
- 協力会社支払設定: 協力会社へ支払う金額のルール
- 給料明細 / 請求書 / 支払証明書: 結果。実績を再入力しない

## 削除手順
1. UI重複を隠す。
2. 正しい設定へ参照先を統一。
3. 旧列のread/writeを検索・監査。
4. 本番データを正データへ移行。
5. 旧列readを停止。
6. 一定期間の回帰確認後のみDB列を削除。
