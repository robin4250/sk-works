These disposable PostgreSQL rows come from actual attendance and payroll-setting triggers, not production employee data. The monthly row has base 300000 and overtime 6000; the second row adds the registered deduction 1100. IDs generated at runtime are omitted. Reproduce:

```sh
node tool/generate_payroll_pdf_money_fixtures.mjs /path/to/pglite/dist/index.js supabase/migrations/20261008042817_prevent_paid_leave_attendance_overlap.sql supabase/migrations/20261008043151_align_future_attendance_monthly_payroll_boundary.sql supabase/migrations/20261008045401_preserve_payroll_named_financial_details.sql
```

Extended daily/hourly/monthly cases use half a day of each of day/night/holiday/holiday-night, one overtime hour and half an early hour per category, family allowance 2000 and transport 1000, duplicate-name configured earnings 5000+2000 and deductions 1100+400. These expose omitted family/non-day monthly base and overwritten legacy duplicate-name mirrors. Regenerate with the reviewed forward fix as an additional final migration argument before committing corrected fixtures.
