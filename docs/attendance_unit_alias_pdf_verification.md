# Attendance unit alias PDF regression

Test-only child of allowance contract PR #1152. Product Dart/SQL, existing fixtures,
permissions, data and UI are unchanged. The new exporter runs the actual old unit
RPC and staged candidate in a fresh in-memory PGlite database with synthetic data.
It records the before/rename/retire maps. The test feeds each map to an unchanged
past attendance month and calls the real month and worker-list PDF builders.

Existing Flutter CI supplies its adopted Japanese font, PGlite and PyMuPDF. A
test-scoped public printing cache supplies that font for both requested weights;
no network download or Helvetica fallback is accepted. The text assertions check
both summary and row units, and page raster hashes must remain identical across
all three phases. Six PDFs, two PNGs and inspection JSON are saved under the
existing PDF artifact directory. This validates unit display, not exact production
bold typography, printing hardware, native sharing, real database JWTs or iPhone.

No historic unit before first adoption can be reconstructed. Conflicting same-name
unit edits remain rejected by the staged contract. The current PDF has no dated
unit source and defaults an unknown name to 回; this test demonstrates preservation
through the compatibility map rather than pretending that fallback is historical
evidence. This does not connect new common allowances to payroll calculation.
