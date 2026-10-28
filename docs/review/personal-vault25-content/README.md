# Own PDF content observations — review only

The independent PyMuPDF worker binds exact PDF bytes to the expected digest, checks owner text, and rejects fixture private text in extracted text or metadata, attachments, annotations, links, forms, images, XML metadata and optional content. It emits only digests/counts; it does not emit document text or a delivery `passed` receipt.

This is **not** a complete PDF privacy validator or authenticated owner check. Text extraction does not prove arbitrary PDFs have no hidden information, unknown data is not covered by fixture markers, and trusted owner/source snapshot binding, resource-isolated production service, independent attestation and immutable retention remain unimplemented. Never translate these observations into `trustedPrivacyProof` / `own-snapshot-v1`. No endpoint is exposed or feature activated.

The existing own-payroll renderer fixture is reused for a real generated PDF test in CI. It injects foreign remarks, manager notes and seal secrets into the input and checks generated PDF observations. Local Python fixture tests cover metadata/private-text leaks, attachments, annotations, links, forms and wrong owner/digest. PyMuPDF is pinned to 1.26.6; official Document/Page APIs were reviewed. Local Flutter/Dart was not executed; generated renderer verification runs only in CI.

The image restriction applies only to this text-only payroll fixture. Legitimate attendance/payroll originals can contain signatures or seals; this utility must not remove, discard or declare such originals unsafe. A future inspector must validate permitted image provenance/content against the frozen own-record rather than blanket-reject production images. No existing original or renderer behavior is changed by this candidate.

## Known active PDF structures

The text-only observation worker now rejects known document/page actions, JavaScript name trees (including escaped PDF names), XFA and rich-media action dictionaries before text extraction. It inspects parsed dictionary keys/paths across a bounded maximum of 50,000 PDF objects; it does not search raw byte strings or rewrite the input. This closes a demonstrated case where an annotation-free `OpenAction` JavaScript fixture passed the earlier observations. Tests cover direct/indirect and escaped names, name trees and page additional actions; ordinary action words in page text remain accepted.

These checks are a narrow safety improvement to this review-only observer, not a full PDF security/privacy scanner, independent source-owner validation, or permission to issue a `passed` delivery proof. Hidden/unrecognized PDF data, source authenticity and immutable Storage remain unresolved. Legitimate signature/seal originals are unchanged and are not deleted or sanitized. The existing image limitation remains restricted to the text-only generated fixture.

Reference: [PyMuPDF parsed dictionary inspection](https://pymupdf.readthedocs.io/en/latest/document.html#Document.xref_get_keys). Local Python 5 test methods pass with PyMuPDF 1.26.6. Flutter/rendered-document verification is left to the existing dedicated CI; no local Flutter/Dart was run.
