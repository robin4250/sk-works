# Arbitrary PNG company seal registration — review candidate

Baseline main c8216d9a31e0d8340c9ec123307907bc148191a8; Issue #273.

## Existing state and reuse

CompanySealDesign contains three immutable company-specific bundled PNG assets only. CompanySealSettingsPage offers selection/preview/save, not a file uploader. The older company_private_billing_settings.invoice_seal_base64 and save_invoice_branding contract still exist, but current common PDF rendering does not read that field. Adding a picker that only fills it would not change the reports.

This candidate preserves the existing bundled/legacy/Reisho choices. A separate company PNG selection defaults OFF and takes precedence only while explicitly enabled. No company style, existing financial row, old image, old invoice branding value or Storage object is rewritten.

## Implemented candidate

- Company seal settings gains a PNG file picker, container validation, actual Flutter image decode, required shared-PDF preview, confirmed revision save and OFF control.
- Backend-missing/mismatched settings cannot report successful registration. Existing design selection remains available.
- Private immutable PNG versions hold exact company/name, SHA-256, dimensions, bytes and creator. Selection uses an optimistic revision. RPC authorization requires the exact company owner/admin and allowed account, before and after the company lock.
- PNG limits: 1 MiB, 32–2048px each side, 8-bit RGB/RGBA, non-interlaced/static. Client checks signature/chunks/CRC/SHA, then decodes before preview/save. Server independently validates size/signature/IHDR/dimensions/IEND/hash; it does not contain a PNG inflater. Native full-codec validation is therefore still a rollout condition.
- New version-2 document metadata freezes version UUID, exact PNG bytes/hash, registered name and company. Existing p_new=false metadata is returned unchanged. Current selection changes cannot change old PDFs.
- Saved invoice/payroll/payment/order/acceptance and site-contract seal rendering use the same frozen PNG object. Existing ON/OFF controls remain in place.
- Self-contained snapshots avoid live external image downloads, URL expiry and Storage overwrite problems. At the 1 MiB limit, base64 increases financial-row size; ordinary compact seal PNGs should be preferred.

## Verification

Passed locally: tool/verify_company_seal_uploaded_png.mjs with PGlite. Tests cover owner access, outsider/table denial, immutable versions, hash/magic/dimension rejection, stale revision, replacement preserving old saved PNG, OFF restoring the existing style, and company-name drift rejection.

Dart tests added but NOT run here (Flutter SDK absent): validator immutability/corruption, backend-missing widget, invalid picker input, HTTP repository save confirmation, and five real production PDF paths. tool/verify_company_uploaded_seal_pdfs.py checks each PDF contains its 32x32 fixture image and alpha mask after those tests produce output. Parent CI must run analysis/tests and Poppler inspection.

Run from repository root:
node tool/verify_company_seal_uploaded_png.mjs /absolute/path/to/pglite/dist/index.js
flutter test test/company_uploaded_seal_png_test.dart test/company_seal_png_uploader_test.dart test/company_uploaded_seal_pdf_test.dart
python3 tool/verify_company_uploaded_seal_pdfs.py

## Remaining integration / rollout gates

This is a REVIEW-ONLY SQL file, outside migrations. It has not touched production. Its existing snapshot-function MD5 guard is 5e29407c55cfe7fa33eb7933a38d2af7; real catalog/ACL checkpoint and native restoration/undo rehearsal are required before any deployment. New clients must ship before any company enables uploaded PNG; old clients reject version-2 metadata.

The unsaved/current invoice and payment preview paths now use the guarded company_current_uploaded_seal RPC and pass the result into CompanySealSnapshot.forPreview. Only owner/admin/manager in the exact company may read it. Missing RPC falls back to the existing company design; real read failures do not silently select a different seal. Invoice output stays blocked; saved payment rows remain readable while unavailable in-memory previews are omitted. Frozen documents retain their saved bytes. payment_certificate_repository.dart stacks on PR #1294 head fe30ac48686ebc1b1a66ae134477ba48aedd0102; other modified files use main c8216d9.

Further required checks: issued JWT/PostgREST permissions, actual image codec/PDF output, guarded deployment/undo, new Release build/device save–reload–PDF/share and existing snapshot regression. No release upload or production activation has occurred.
