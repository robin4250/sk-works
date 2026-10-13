# Translation coverage inventory

Display languages and country rules are independent. Japanese country rules (JPY, Japanese document keys and telephone rules) remain active when English is selected. No foreign tax or leave rules are introduced.

The application root listens to the language notifier and provides Japanese/English Flutter localization delegates. A language change updates the locale without replacing the navigator. Existing routes call `SkoLanguageController.watch(context)` to subscribe through Localizations; this preserves editing controllers and navigation history. This audit does not claim that every screen is fully translated.

| Screen | Static Text literals reviewed | English resource matches |
| --- | ---: | ---: |
| `lib/features/settings/company_module_settings_page.dart` | 8 | 2 |
| `lib/features/settings/company_rate_settings_page.dart` | 8 | 2 |
| `lib/features/daily_reports/daily_report_pending_notice.dart` | 2 | 2 |
| `lib/features/payroll/payroll_confirmation_settings_page.dart` | 12 | 1 |

Counts cover only directly written static Text literals. They do not count ternary strings, interpolated strings, labels in models, server messages, or translated calls. A matching resource alone does not wire a widget to translation.

Fixed templates use `SkoLanguageController.trParams(template, parameters)`. Parameters are inserted once, verbatim; company names, person names, amounts, dates and server error details are not translated. Missing translations retain their Japanese source wording. Missing placeholders remain visible instead of silently losing information.

New resource coverage: company feature ON/OFF instructions, saved legacy rate labels, rate sources, missing-rate warnings, clocked-in/report-pending notice, review/retry actions and parameterized load/save errors.

Remaining work: feature owners must use `tr` or `trParams` for new wording and call `watch(context)` where an already-open route needs immediate switching. Country expansion needs an explicit validated country pack; choosing English does not create US business rules.

Implemented route coverage in this batch: company feature/rate settings, individual payroll settings, payment certificates/settings, daily report and pending notice. Feature owners use `tr`/`trParams` and locale subscriptions; resource coverage was checked for their directly referenced literal translation keys. Stored allowance names, employee/company names, formulas and server error details remain user data. Other screens and report PDFs still need separate audits; this is not full application translation coverage.
