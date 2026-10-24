"""Independent verification of synthetic SQL-to-approved-PDF exports."""
import hashlib
import json
import pathlib
import sys
import unicodedata

import fitz


def normalized(value):
    return ''.join(unicodedata.normalize('NFKC', value).split())


root = pathlib.Path(sys.argv[1]).resolve()
manifest = json.loads((root / 'manifest.json').read_text())
assert manifest['synthetic_fixture'] is True and manifest['schema'] == 1
assert len(manifest['files']) == 4
for item in manifest['files']:
    pdf = root / item['file']
    assert pdf.parent == root and pdf.suffix == '.pdf'
    data = pdf.read_bytes()
    assert hashlib.sha256(data).hexdigest() == item['pdf_sha256']
    document = fitz.open(stream=data, filetype='pdf')
    assert len(document) == item['expected_pages'] == 1
    text = normalized(''.join(page.get_text() for page in document))
    for expected in item['expected_texts']:
        assert normalized(expected) in text, (item['file'], 'missing text', expected)
    for page in document:
        for word in page.get_text('words'):
            assert fitz.Rect(word[:4]) in (page.rect + (-1, -1, 1, 1)), (item['file'], 'text outside page')
        page.get_pixmap(matrix=fitz.Matrix(1.5, 1.5)).save(root / (pdf.stem + '.png'))
    if item['registered_png_file'] is not None:
        source = root / item['registered_png_file']
        assert source.parent == root
        png = source.read_bytes()
        assert hashlib.sha256(png).hexdigest() == item['registered_png_sha256']
        expected_image = fitz.Pixmap(png)
        if not expected_image.alpha:
            expected_image = fitz.Pixmap(expected_image, 1)
        assert (expected_image.width, expected_image.height) == (item['registered_png_width'], item['registered_png_height'])
        matched = False
        for page in document:
            for image in page.get_images(full=True):
                pixmap = fitz.Pixmap(document, image[0])
                if image[1]:
                    pixmap = fitz.Pixmap(pixmap, fitz.Pixmap(document, image[1]))
                if not pixmap.alpha:
                    pixmap = fitz.Pixmap(pixmap, 1)
                if (pixmap.width, pixmap.height, pixmap.samples) == (expected_image.width, expected_image.height, expected_image.samples):
                    matched = True
                    assert page.get_image_rects(image[0]), 'registered seal is not placed on page'
        assert matched, (item['file'], 'registered seal pixels changed or missing')
print('PASS four approved PDFs: SQL text, amounts, registered seal pixels, hashes and page bounds')
