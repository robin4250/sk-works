"""Approved SHA942bad918b696b4c2c527dbf2fca9d050e4fb38a3674cff115eb0755793b8a18.
Measure actual glyph advances and ensure every prescribed U+3000 gap has no ink.
"""
import json
import math
from pathlib import Path
import fitz

root = Path('build/trade-document-label-spacing')
geometry = json.loads(Path('docs/fixtures/trade-document-design/original-design-20261029.json').read_text())
results = []
for kind in ['order', 'acceptance']:
    document = fitz.open(root / f'{kind}.pdf')
    assert len(document) == 1
    page = document[0]
    assert abs(page.rect.width - 595.27559) < .02 and abs(page.rect.height - 841.88976) < .02
    g = geometry[kind]
    chars = [dict(c, size=s['size'], font=s['font'])
             for b in page.get_text('rawdict')['blocks']
             for line in b.get('lines', []) for s in line['spans'] for c in s['chars']]
    ledger = ('施　工　単　価　内　訳　書', 130.0) if kind == 'order' else ('工　事　費　内　訳　書', 110.0)
    cases = [(ledger[0], ledger[1], 10, 34, page.rect.width - 34, 9),
             ('項　　　目', 42.5, 8.5, g['grid_columns'][0], g['grid_columns'][1], 10),
             ('数　量', 25.5, 8.5, g['grid_columns'][1], g['grid_columns'][2], 10)]
    pix = page.get_pixmap(matrix=fitz.Matrix(3, 3), colorspace=fitz.csRGB, alpha=False)
    for label, expected, size, x0, x1, row in cases:
        top, bottom = page.rect.height - g['ys'][row], page.rect.height - g['ys'][row + 1]
        selected = sorted([c for c in chars if c['c'] in label.replace('\u3000', '')
                           and x0 <= c['bbox'][0] < x1
                           and top <= (c['bbox'][1] + c['bbox'][3]) / 2 <= bottom],
                          key=lambda c: c['bbox'][0])
        assert ''.join(c['c'] for c in selected) == label.replace('\u3000', ''), (kind, label, selected)
        assert all(abs(c['size'] - size) < .01 and 'NotoSansJP' in c['font'] for c in selected)
        width = selected[-1]['bbox'][2] - selected[0]['bbox'][0]
        assert abs(width - expected) < .03, (kind, label, 'approved width', expected, 'actual', width)
        assert abs((selected[0]['bbox'][0] + selected[-1]['bbox'][2]) / 2 - (x0 + x1) / 2) < .03
        segments = label.split('\u3000')
        # All three approved target labels contain one-glyph runs; consecutive
        # spaces in 項/目 remain separate full-em advances.
        visible = [(i, part) for i, part in enumerate(segments) if part]
        for index, ((a, _), (b, _)) in enumerate(zip(visible, visible[1:])):
            first, second = selected[index], selected[index + 1]
            gap = second['bbox'][0] - first['bbox'][2]
            assert abs(gap - (b - a) * size) < .03, (kind, label, gap, (b-a)*size)
            left, right = math.ceil((first['bbox'][2] + .75) * 3), math.floor((second['bbox'][0] - .75) * 3)
            high = math.ceil(max(first['bbox'][1], second['bbox'][1]) * 3)
            low = math.floor(min(first['bbox'][3], second['bbox'][3]) * 3)
            assert right > left and low > high
            assert all(min(pix.pixel(x, y)) >= 245 for y in range(high, low) for x in range(left, right)), (kind, label, 'space contains ink')
        for char in selected:
            r = fitz.Rect(char['bbox'])
            assert any(min(pix.pixel(x, y)) < 128 for y in range(math.ceil(r.y0*3), math.floor(r.y1*3))
                       for x in range(math.ceil(r.x0*3), math.floor(r.x1*3))), (kind, label, 'missing glyph ink')
        results.append({'kind': kind, 'label': label, 'width_pt': width, 'font_size': size, 'space_ink': False})
    text = page.get_text()
    assert '第一明細' in text and '第九明細' in text
    page.get_pixmap(matrix=fitz.Matrix(1.5, 1.5)).save(root / f'{kind}.png')
(root / 'spacing-proof.json').write_text(json.dumps(results, ensure_ascii=False, indent=2))
print('PASS approved static widths130/110/42.5/25.5pt, full-em advances, white U3000 gaps, visible same-font glyphs and fixed front geometry')
