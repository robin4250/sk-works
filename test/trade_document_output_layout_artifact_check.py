"""Checks actual vector PDF geometry/content, then emits visual proof PNGs."""
from pathlib import Path
import fitz

root = Path('build/trade-document-output-layout')
a4 = fitz.open(root / 'a4TwoPages.pdf')
a3 = fitz.open(root / 'a3Landscape.pdf')
duplex = fitz.open(root / 'a4Duplex.pdf')
legacy = fitz.open(root / 'legacy-original.pdf')
assert (len(a4), len(a3), len(duplex), len(legacy)) == (2, 1, 2, 1)
w, h = 210 * 72 / 25.4, 297 * 72 / 25.4
for doc in [a4, duplex, legacy]:
    for page in doc:
        assert abs(page.rect.width - w) < .02 and abs(page.rect.height - h) < .02
assert abs(a3[0].rect.width - 2 * w) < .02 and abs(a3[0].rect.height - h) < .02
assert 'LEGACY SAVED ORIGINAL' in legacy[0].get_text()
assert 'TERMS COMPLETE' not in legacy[0].get_text()


def spans(page):
    return [s for b in page.get_text('dict')['blocks'] for l in b.get('lines', []) for s in l['spans']]


def by_side(doc, side):
    return {s['text']: s for p in doc for s in spans(p) if s['text'].startswith(side)}


for side, idx in [('FRONT', 0), ('TERMS', 1)]:
    baseline = by_side(a4, side)
    assert len(baseline) == 29, (side, len(baseline))
    for edge in ['TOP-LEFT', 'TOP-RIGHT', 'BOTTOM-LEFT', 'BOTTOM-RIGHT']:
        assert f'{side}-{edge}' in baseline
    for i in range(1, 25):
        assert f'{side} ITEM {i:02d} retained vector text' in baseline
    for doc, dx in [(a3, idx * w), (duplex, 0)]:
        actual = by_side(doc, side)
        assert baseline.keys() == actual.keys()
        for text, original in baseline.items():
            candidate = actual[text]
            assert abs(original['size'] - candidate['size']) < .001, text
            expected = tuple(v + (dx if i % 2 == 0 else 0) for i, v in enumerate(original['bbox']))
            assert max(abs(a - b) for a, b in zip(expected, candidate['bbox'])) < .03, (text, expected, candidate['bbox'])

for doc, name in [(a4, 'a4TwoPages'), (a3, 'a3Landscape'), (duplex, 'a4Duplex')]:
    kind, preferences = doc.xref_get_key(doc.pdf_catalog(), 'ViewerPreferences')
    assert kind == 'dict' and '/PrintScaling/None' in preferences.replace(' ', '')
    assert ('/DuplexFlipLongEdge' in preferences) == (name == 'a4Duplex')
    for i, page in enumerate(doc):
        assert not page.get_images(), 'No rasterized canvas is permitted'
        for span in spans(page):
            x0, y0, x1, y1 = span['bbox']
            assert x0 >= 0 and y0 >= 0 and x1 <= page.rect.width and y1 <= page.rect.height, span
        page.get_pixmap(matrix=fitz.Matrix(1, 1)).save(root / f'{name}-{i+1}.png')
print('PASS page count/size, all 58 text spans, 100% A4 vector geometry, edge markers, no crop/raster, duplex preferences and legacy preservation')
