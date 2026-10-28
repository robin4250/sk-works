# Own PDF content observations — review only

The independent PyMuPDF worker binds exact PDF bytes to the expected digest, checks owner text, and rejects fixture private text in extracted text or metadata, attachments, annotations, links, forms, images, XML metadata and optional content. It emits only digests/counts; it does not emit document text or a delivery `passed` receipt.

This is **not** a complete PDF privacy validator or authenticated owner check. Text extraction does not prove arbitrary PDFs have no hidden information, unknown data is not covered by fixture markers, and trusted owner/source snapshot binding, resource-isolated production service, independent attestation and immutable retention remain unimplemented. Never translate these observations into `trustedPrivacyProof` / `own-snapshot-v1`. No endpoint is exposed or feature activated.

The existing own-payroll renderer fixture is reused for a real generated PDF test in CI. It injects foreign remarks, manager notes and seal secrets into the input and checks generated PDF observations. Local Python fixture tests cover metadata/private-text leaks, attachments, annotations, links, forms and wrong owner/digest. PyMuPDF is pinned to 1.26.6; official Document/Page APIs were reviewed. Local Flutter/Dart was not executed; generated renderer verification runs only in CI.
