# 会社給与設定・社員情報の本番反映記録

元関数定義: branch `backup/pre-employee-confirmation-20261008` commit `dd7605ca4e048c3ecb8a871d1117c2c338c547c7`。関数定義の保存であり、登録データ・iPhoneのバックアップではない。

| ローカル migration | 本番 version |
|---|---|
| 20261008004843_employee_registered_identity.sql | 20261008011202 |
| 20261008004129_payroll_assigned_confirmation_notifications.sql | 20261008034624 |
| 20261008010518_payroll_confirmation_document_metadata.sql | 20261008034635 |
| 20261008035104_stabilize_automatic_payroll_totals.sql | 20261008035559 |
| 20261008034850_payroll_default_company_confirmer.sql | 20261008035833 |
| 20261008035432_certificate_canonical_snapshot_math.sql | 20261008041946 |
| 20261008035509_invoice_registered_method_amounts_and_formula_labels.sql | 20261008041948 |
| 20261008040303_payroll_confirmer_visibility_guard.sql | 20261008042028 |
| 20261008040428_generate_fixed_monthly_payroll_without_attendance.sql | 20261008042030 |
| 20261008042058_fix_managed_attendance_overnight_chronology.sql | 20261008042530 |
| 20261008042817_prevent_paid_leave_attendance_overlap.sql | 20261008043422 |
| 20261008043151_align_future_attendance_monthly_payroll_boundary.sql | 20261008043424 |
| 20261008043823_atomic_company_rate_and_allowance_units_save.sql | 20261008052056 |
| 20261008044046_validate_registered_calculation_sources.sql | 20261008052058 |
| 20261008045401_preserve_payroll_named_financial_details.sql | 20261008052138 |

Supabase apply_migration が生成する本番versionとローカルCLIファイル時刻は別管理。古いmigrationをrename・再適用・ledger修正しない。

給与条件警告 migration `20261008044613` は最初の本番適用で自動承認レビューに拒否され、未適用。理由は返されなかった。既存トリガーを削除せず、未登録時のみ追加する方式に変更し、再適用でトリガーOIDが維持される実SQL検証に成功。再適用結果は確認後に追記する。上記3件反映後も社員8件・給与明細2件・会社2件の件数は維持。

反映後の読み取り検証: 登録会社・社員・給与明細・確認行の件数は反映前と同じ。新確認3表RLS有効、authenticated直接UPDATE不可。日次通知cron `payroll-confirmation-daily-jst` 有効、UTC15:00（JST00:00）。実際の確認日時と履歴を表示日付で書き換えない。

計算修正前の関数定義は `backup/pre-calculation-repairs-20261008` commit `1d576a530bf5b822a912ba7a8240357dbf960ad7` に保存。最新4件反映後も社員8件・給与明細2件を維持。内部月給生成関数のauthenticated実行権限なし。既存cronで月給下書き生成後に確認通知を実行し、過去月の一括再計算は行わない。
