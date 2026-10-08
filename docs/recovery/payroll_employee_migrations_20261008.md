# 会社給与設定・社員情報の本番反映記録

元関数定義: branch `backup/pre-employee-confirmation-20261008` commit `dd7605ca4e048c3ecb8a871d1117c2c338c547c7`。関数定義の保存であり、登録データ・iPhoneのバックアップではない。

| ローカル migration | 本番 version |
|---|---|
| 20261008004843_employee_registered_identity.sql | 20261008011202 |
| 20261008004129_payroll_assigned_confirmation_notifications.sql | 20261008034624 |
| 20261008010518_payroll_confirmation_document_metadata.sql | 20261008034635 |

Supabase apply_migration が生成する本番versionとローカルCLIファイル時刻は別管理。古いmigrationをrename・再適用・ledger修正しない。

反映後の読み取り検証: 登録会社・社員・給与明細・確認行の件数は反映前と同じ。新確認3表RLS有効、authenticated直接UPDATE不可。日次通知cron `payroll-confirmation-daily-jst` 有効、UTC15:00（JST00:00）。実際の確認日時と履歴を表示日付で書き換えない。
