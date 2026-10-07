# Adopted report masters and verification

The original invoice v8, payroll v4 and square-seal A reference are immutable design masters. The square-seal image is a design reference only; application PDFs generate each registered company name dynamically and never embed this particular company's image.

Generate actual Flutter PDF fixtures with Flutter 3.47.5:

```bash
python -m pip install PyMuPDF==1.26.6 fonttools==4.61.1
python tool/prepare_pdf_fixture_font.py
SKO_PDF_FONT_PATH=build/pdf-fixtures/NotoSansJP-Regular.ttf SKO_PDF_OUTPUT_DIR=build/pdf-fixtures flutter test test/adopted_invoice_pdf_generation_test.dart test/adopted_payroll_pdf_generation_test.dart
```

Flutter CI runs these tests and uploads generated PDFs as `adopted-report-pdf-comparison`. Compare the actual output against these masters visually with PyMuPDF, including all text, seven invoice columns/35 rows, equal payroll panel widths, totals, bank fields and stamps. CI alone does not certify visual equality.

On 2026-10-08 JST the user explicitly accepted a similar company seal appearance (「似たような感じで良いですよ」). The shared seal now uses the bundled licensed Aoyagi Reisho Shimo font, thick rounded red frame and vertical registered-company lettering, with the body font as a rare-character fallback. Exact seal-script glyph equality is no longer the acceptance criterion; adopted report layout remains unchanged.

Individual invoice-line dates have no verified source and are left blank rather than invented. Customer address is propagated from the saved snapshot or current customer billing address. Actual generated PDFs and comparison evidence are preserved under `generated/84b2002/` and `verification_84b2002.md`; subsequent typography and seal fixes need fresh comparison. Keep PR #745 Draft until final generated PDFs, CI and registered-data mapping have been verified.

Approval and bank migrations are additive and have isolated PostgreSQL behavioral verification. Production application and physical iPhone Release verification remain separate release requirements.
