# Registered invoice details and rate samples

Actual Flutter PDF artifacts from source 4f41ae089363582d582176d72c4f81cbc60e0433, Actions run 37708143819, artifact 11520980812. All three samples are A4 single pages and were rendered/inspected.

- Customer contact: registered phone appears at x38–87.19, y166.2–174.89 inside the original recipient frame ending y176; address remains visible.
- Welfare rates: separate saved 3%/3,000 and 1.5%/1,500 rows, subtotal204,500 + tax20,450 =224,950. Existing saved welfare rows are not appended twice.
- Ditto: normal site name starts x65, repeated mark x94.7, an explicit29.7pt indent inside original site column.

These invoice fixtures passed their actual PDF tests. That full CI run failed on an unrelated short-company payroll translation direction and source-format checks; those were corrected in the subsequent source commit, whose final CI must pass before release. This archive does not claim device printing or final-source CI completion.

Regenerate with pinned Flutter3.47.5, workflow-pinned PyMuPDF/fontTools, prepared Japanese font from tool/prepare_pdf_fixture_font.py, SKO_PDF_FONT_PATH and SKO_PDF_OUTPUT_DIR, then flutter test test/adopted_invoice_pdf_generation_test.dart. Original adopted masters are unchanged.
