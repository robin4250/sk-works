# SKO pre-device Release candidate — 2026-10-04

Base main SHA: `d5d81d6f59981392876bd15f9eebc9a6d6cd50ea`

Included final slices:
- #591 zero-value payroll/invoice/payment-certificate draft generation and missing-setting attention
- #592 payroll review list, manager visibility and viewer confirmation workflow
- #593 employee payroll confirmed/unconfirmed status in screen and PDF
- #594 printable payment certificate PDF
- #595 payroll review menu connection

Production Supabase migrations verified through:
- 20261004104733 allow_zero_draft_generation_and_payment_certificates
- 20261004105043 dedupe_generation_setting_notifications
- 20261004105505 harden_generation_draft_policies
- 20261004110609 add_payroll_review_confirmation
- 20261004110735 fix_payroll_review_period_variable
- 20261004111111 generate_invoice_without_customer_setting
- 20261004111410 refresh_generation_attention_on_site_customer
- 20261004111520 confirm_payroll_review_month

Release-device invariant:
- Correct iOS Bundle ID: `com.skworks.skWorks`
- Never install to `com.robin4250.sko`
- Release only; no Debug / flutter run
- Preserve the original installed SKO app
