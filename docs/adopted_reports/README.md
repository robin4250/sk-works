# Adopted report masters and verification

The original invoice v8, payroll v4 and square-seal A reference are immutable design masters. The square-seal image is a design reference only; application PDFs generate each registered company name dynamically and never embed this particular company's image.

Generate actual Flutter PDF fixtures with Flutter 3.47.5:

```bash
python -m pip install PyMuPDF==1.26.6 fonttools==4.61.1
python tool/prepare_pdf_fixture_font.py
SKO_PDF_FONT_PATH=build/pdf-fixtures/NotoSansJP-Regular.ttf SKO_PDF_OUTPUT_DIR=build/pdf-fixtures flutter test test/adopted_invoice_pdf_generation_test.dart test/adopted_payroll_pdf_generation_test.dart
```

Flutter CI runs these tests and uploads generated PDFs as `adopted-report-pdf-comparison`. Compare the actual output against these masters visually with PyMuPDF, including all text, seven invoice columns/35 rows, equal payroll panel widths, totals, bank fields and stamps. CI alone does not certify visual equality.

Current unresolved acceptance points: the shared dynamic seal uses the document font rather than the reference's seal-script glyphs; customer address and individual invoice-line dates are not yet present in the current calculation model. No replacement design is adopted. Keep PR #745 Draft until visual comparison and these points are resolved.

Approval and bank migrations are additive and have isolated PostgreSQL behavioral verification. Production application and physical iPhone Release verification remain separate release requirements.
