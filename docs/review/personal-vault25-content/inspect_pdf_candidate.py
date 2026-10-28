"""Review-only text-PDF inspection. This is not an owner-privacy proof.

Run only in an isolated, resource-bounded worker. The trusted caller must bind
the input digest and expected owner to an authenticated frozen snapshot. Text
extraction cannot prove that arbitrary PDF bytes contain no hidden information;
never adapt this result into delivery.trustedPrivacyProof's passed=true receipt.
"""
import hashlib
import re
import pymupdf


def reject_active_structures(doc):
    """Reject known active structures without rewriting the original PDF.

    This bounded inspection is not a complete PDF content/privacy validator.
    PyMuPDF resolves PDF name escaping and indirect dictionary paths here;
    scanning the original byte string would miss encoded or compressed names.
    """
    if doc.xref_length() > 50_000:
        raise ValueError("vault_content_object_limit")
    active_keys = {"OpenAction", "AA", "JS", "JavaScript", "XFA",
                   "RichMediaContent", "RichMediaSettings"}
    action_names = {"/GoTo", "/GoToR", "/GoToE", "/Launch", "/Thread", "/URI",
                    "/Sound", "/Movie", "/Hide", "/Named", "/SubmitForm",
                    "/ResetForm", "/ImportData", "/JavaScript", "/SetOCGState",
                    "/Rendition", "/Trans", "/GoTo3DView"}
    for xref in range(1, doc.xref_length()):
        if active_keys.intersection(doc.xref_get_keys(xref)):
            raise ValueError("vault_content_active_structure_rejected")
        if doc.xref_get_key(xref, "Names/JavaScript")[0] != "null":
            raise ValueError("vault_content_active_structure_rejected")
        for key in ("S", "A/S", "Next/S"):
            kind, value = doc.xref_get_key(xref, key)
            if kind == "name" and value in action_names:
                raise ValueError("vault_content_active_structure_rejected")


def inspect_candidate(data, *, expected_sha256, expected_owner, forbidden_markers=()):
    if (not isinstance(data, bytes) or not 12 <= len(data) <= 50 * 1024 * 1024
            or not isinstance(expected_sha256, str)
            or not re.fullmatch(r"[a-f0-9]{64}", expected_sha256)
            or hashlib.sha256(data).hexdigest() != expected_sha256
            or not isinstance(expected_owner, str) or not expected_owner.strip()
            or len(expected_owner) > 200
            or not isinstance(forbidden_markers, (list, tuple))
            or any(not isinstance(x, str) or not x or len(x) > 200 for x in forbidden_markers)):
        raise ValueError("vault_content_input_rejected")
    with pymupdf.open(stream=data, filetype="pdf") as doc:
        if (not doc.is_pdf or doc.is_encrypted or doc.is_repaired
                or not 1 <= doc.page_count <= 100 or doc.embfile_count()
                or doc.get_ocgs() or doc.get_xml_metadata()):
            raise ValueError("vault_content_structure_rejected")
        reject_active_structures(doc)
        pages = []
        for page in doc:
            if (list(page.annots() or ()) or list(page.widgets() or ())
                    or page.get_links() or page.get_images(full=True)):
                raise ValueError("vault_content_extras_rejected")
            text = page.get_text()
            if len(text) > 200_000:
                raise ValueError("vault_content_text_limit")
            pages.append(text)
        text = "\n".join(pages)
        metadata = "\n".join(str(x or "") for x in doc.metadata.values())
        if expected_owner not in text or any(x in text or x in metadata for x in forbidden_markers):
            raise ValueError("vault_content_evidence_rejected")
        return {
            "candidate_policy": "text-pdf-observations-v1",
            "pdf_sha256": expected_sha256,
            "page_count": doc.page_count,
            "text_sha256": hashlib.sha256(text.encode()).hexdigest(),
        }

