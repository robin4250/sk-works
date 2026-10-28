import hashlib
import unittest
import pymupdf
from inspect_pdf_candidate import inspect_candidate


class InspectionCandidateTest(unittest.TestCase):
    def build(self, extra=None):
        with pymupdf.open() as doc:
            page = doc.new_page()
            page.insert_text((72, 72), "Only Owner\nPayroll fixture 90000")
            if extra:
                extra(doc, page)
            return doc.tobytes()

    def inspect(self, data, **kwargs):
        return inspect_candidate(data, expected_sha256=hashlib.sha256(data).hexdigest(),
                                 expected_owner="Only Owner", **kwargs)

    def test_observations_are_bound_to_exact_bytes_and_not_a_delivery_proof(self):
        data = self.build()
        result = self.inspect(data)
        self.assertEqual(result["pdf_sha256"], hashlib.sha256(data).hexdigest())
        self.assertEqual(result["page_count"], 1)
        self.assertNotIn("passed", result)
        self.assertNotIn("text", result)
        with self.assertRaises(ValueError):
            inspect_candidate(data, expected_sha256="a" * 64, expected_owner="Only Owner")
        with self.assertRaises(ValueError):
            inspect_candidate(data, expected_sha256=hashlib.sha256(data).hexdigest(), expected_owner="Other Owner")

    def test_text_and_metadata_leakage_rejected(self):
        for extra in [lambda d, p: p.insert_text((72, 100), "OTHER_PRIVATE"),
                      lambda d, p: d.set_metadata({"subject": "OTHER_PRIVATE"})]:
            with self.assertRaises(ValueError):
                self.inspect(self.build(extra), forbidden_markers=["OTHER_PRIVATE"])

    def test_attachments_annotations_links_and_forms_rejected(self):
        def widget(d, p):
            w = pymupdf.Widget()
            w.field_name = "secret"
            w.field_type = pymupdf.PDF_WIDGET_TYPE_TEXT
            w.rect = pymupdf.Rect(10, 10, 100, 30)
            p.add_widget(w)
        extras = [lambda d, p: d.embfile_add("hidden.txt", b"private"),
                  lambda d, p: p.add_text_annot((10, 10), "private"),
                  lambda d, p: p.insert_link({"kind": pymupdf.LINK_URI,
                                             "from": pymupdf.Rect(10, 10, 50, 20),
                                             "uri": "https://invalid.invalid/private"}), widget]
        for extra in extras:
            with self.subTest(extra=extra), self.assertRaises(ValueError):
                self.inspect(self.build(extra))


if __name__ == "__main__":
    unittest.main()
