# Three company-specific PNG seal designs

User replaced the five-real-font requirement with three similar company-specific
PNG designs, retaining the approved bold mark and adding worn ink. The immutable
asset catalog binds company UUID, exact name, style version and SHA-256. Other
companies are not offered these designs, even if their names coincide. This is
not an arbitrary-company text generator or user-upload screen.

Existing owner/admin settings RPCs expose the three choices only after migration.
Preview remains mandatory before saving. Shared PDF rendering overlays alpha PNG
at the existing seal location/size, respecting the existing ON/OFF behavior.
New document snapshots retain selected style, name and company UUID. Existing
invoice, payroll and certificate snapshots are not backfilled or rewritten.
Changing company name requires returning its current PNG choice to legacy first.
No automatic company-style UPDATE is included in the migration.

Validation: 14 related Flutter tests, Dart analysis, isolated actual SQL migrations
(including three-document immutable snapshots, viewer/outsider/name guards), and
nine actual report PDFs with alpha masks. Invoice/payroll/payment output rendered
and visually reviewed. Local legacy visibility test requires unavailable python/
PyMuPDF; existing CI performs that separate check. Actual device check follows CI.

Deployment requires migration 20261010160154_company_seal_png_designs.sql and
updated Release app. Existing tax/expense PR #888 has two separate migrations.
The user authorized combined tax, expense and seal Release installation after
completion. No production data, historical report or company style has yet been
changed by this source preparation.
