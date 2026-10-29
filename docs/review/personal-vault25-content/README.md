# Own PDF content observations — review only

The independent PyMuPDF worker binds exact PDF bytes to the expected digest, checks owner text, and rejects fixture private text in extracted text or metadata, attachments, annotations, links, forms, images, XML metadata and optional content. It emits only digests/counts; it does not emit document text or a delivery `passed` receipt.

This is **not** a complete PDF privacy validator or authenticated owner check. Text extraction does not prove arbitrary PDFs have no hidden information, unknown data is not covered by fixture markers, and trusted owner/source snapshot binding, resource-isolated production service, independent attestation and immutable retention remain unimplemented. Never translate these observations into `trustedPrivacyProof` / `own-snapshot-v1`. No endpoint is exposed or feature activated.

The existing own-payroll renderer fixture is reused for a real generated PDF test in CI. It injects foreign remarks, manager notes and seal secrets into the input and checks generated PDF observations. Local Python fixture tests cover metadata/private-text leaks, attachments, annotations, links, forms and wrong owner/digest. PyMuPDF is pinned to 1.26.6; official Document/Page APIs were reviewed. Local Flutter/Dart was not executed; generated renderer verification runs only in CI.

The image restriction applies only to this text-only payroll fixture. Legitimate attendance/payroll originals can contain signatures or seals; this utility must not remove, discard or declare such originals unsafe. A future inspector must validate permitted image provenance/content against the frozen own-record rather than blanket-reject production images. No existing original or renderer behavior is changed by this candidate.

## Known active PDF structures

The text-only observation worker now rejects known document/page actions, JavaScript name trees (including escaped PDF names), XFA and rich-media action dictionaries before text extraction. It inspects parsed dictionary keys/paths across a bounded maximum of 50,000 PDF objects; it does not search raw byte strings or rewrite the input. This closes a demonstrated case where an annotation-free `OpenAction` JavaScript fixture passed the earlier observations. Tests cover direct/indirect and escaped names, name trees and page additional actions; ordinary action words in page text remain accepted.

These checks are a narrow safety improvement to this review-only observer, not a full PDF security/privacy scanner, independent source-owner validation, or permission to issue a `passed` delivery proof. Hidden/unrecognized PDF data, source authenticity and immutable Storage remain unresolved. Legitimate signature/seal originals are unchanged and are not deleted or sanitized. The existing image limitation remains restricted to the text-only generated fixture.

Reference: [PyMuPDF parsed dictionary inspection](https://pymupdf.readthedocs.io/en/latest/document.html#Document.xref_get_keys). Local Python 5 test methods pass with PyMuPDF 1.26.6. Flutter/rendered-document verification is left to the existing dedicated CI; no local Flutter/Dart was run.


## Associated-file bypass regression (2026-10-28)

The prior observer accepted a PDF whose catalog AF array pointed to a Filespec and EmbeddedFile stream containing a forbidden marker: embfile_count() was zero and visible page text belonged to the expected owner. The text-only observer now rejects associated-file (AF/EF), portfolio (Collection), Filespec and EmbeddedFile structures. Tests include catalog references, inline page-associated files and an empty-name-tree portfolio; original bytes remain unchanged. Six Python methods pass locally. Earlier head e351170d generated-renderer CI 40664038909 succeeded; this head requires its own CI.

This closes the demonstrated structural bypass only. It does not authenticate owner/source, inspect every hidden PDF representation, issue a privacy proof, or establish immutable retention. Valid signature/seal originals and production renderer/Storage remain unchanged. No production deployment or activation is performed.

## Process-bounded observer composition (2026-10-29, OFF)

`inspection_worker_candidate.observe_in_worker` runs the existing unchanged observer in a fresh Linux child, default disabled. It validates/snapshots exact input bytes/hash and bounded owner/marker configuration before launch, stages an unlinked private input, then uses a fixed `python -I` worker command. There is no caller-selected worker path, executable, environment or shell. At most two requests per supervisor process are admitted without queueing. The generated own-payroll PDF CI fixture now goes through this supervisor; no payroll renderer/calculation or production route changes.

Before parser import/input decoding the child sets address-space 512 MiB, CPU 3 seconds, regular-file size/core dump zero and open-file limit 32. The parent caps stdout at 4096 bytes, discards stderr, applies one parser/spawn deadline (default 5s, trusted maximum 30s), validates one exact digest/count-only JSON object and kills the owned process group, then reaps its direct child. The leader PID stays reserved with `waitid(...WNOWAIT)` until cleanup. Stalled/overflow/nonzero/malformed/wrong-digest output is a generic unavailable result, with no PDF text, paths, credentials or retry.

This is resource bounding, **not an OS security sandbox**. The child retains host user/filesystem/network permissions, and a deliberately detached process may escape the owned group. Initial process creation and staging filesystem IO are not hard real-time guarantees; host isolation, safe scratch storage, cross-process/tenant admission and resource enforcement remain prerequisites. The per-process semaphore is not a global quota. This candidate must not be deployed as an arbitrary-PDF production service.

It does not authenticate owner/source, inspect unknown hidden PDF data, issue a signed/passed privacy receipt or establish immutable retention. Original bytes, signatures/seals, catalog/RLS and Storage remain untouched. Known images remain unsupported only for the existing text-only fixture; this restriction never deletes or rewrites legitimate originals.

Local Python 16 tests (6 existing + 10 new) pass with PyMuPDF 1.26.6: actual parser success/refusal, byte preservation, disabled/pre-spawn rejection, exact output schema, unbounded stdout/stall cleanup and direct-child reaping, exited leader with surviving group members, cleared environment/closed inherited descriptors, admission release, plus actual child limits checked at parser import. Structural limits-order test is separate from actual child execution. The real Flutter renderer composition still requires its new CI; no local Flutter execution is claimed.

Primary references: [Python resource limits](https://docs.python.org/3/library/resource.html), [subprocess lifecycle/environment](https://docs.python.org/3/library/subprocess.html), [waitid/WNOWAIT](https://docs.python.org/3/library/os.html#os.waitid), [PyMuPDF Document](https://pymupdf.readthedocs.io/en/latest/document.html). No dependencies changed.

The first dedicated CI failed before the generated-renderer test: pip installed PyMuPDF in user site-packages, which isolated Python `-I` correctly excludes. CI now installs the same pinned packages into an isolated venv and explicitly checks import/version under `-I`; both the dedicated observer job and general Flutter PDF verification use that venv. The child still has isolated imports and a cleared environment. No user-site/PYTHONPATH escape or relaxed parser limit was introduced. New-head CI remains required.
