"""Check actual appendix PDFs, using visible text and rendered seal pixels."""
import json
from pathlib import Path
import sys
import fitz

folder = Path(sys.argv[1])
cases = json.loads((folder / 'manifest.json').read_text())
assert len(cases) == 22
summary = []
for case in cases:
    with fitz.open(folder / case['file']) as pdf:
        assert len(pdf) == 1, (case['file'], len(pdf))
        page = pdf[0]
        black = []
        for block in page.get_text('rawdict')['blocks']:
            for line in block.get('lines', []):
                for span in line['spans']:
                    if span.get('color') == 0:
                        black.extend(char for char in span['chars'] if not char['c'].isspace())
        text = ''.join(char['c'] for char in black)
        for value in case['representatives'] + ([] if case.get('empty') else ['1234567890123', '9876543210987']):
            assert value in text, (case['file'], value)
        if case['kind'] == 'order':
            assert '110,000' in text and '10,000' in text, case['file']
        expected_name = ''.join(case['name'].split())
        start = text.find(expected_name)
        assert start >= 0, (case['file'], 'company name missing')
        name_chars = black[start:start + len(expected_name)]
        if name_chars:
            last_center = max((c['bbox'][1] + c['bbox'][3]) / 2 for c in name_chars)
            last_line = [c['bbox'] for c in name_chars
                         if abs((c['bbox'][1] + c['bbox'][3]) / 2 - last_center) < 2]
            name_right = max(b[2] for b in last_line)
            name_middle = (min(b[1] for b in last_line) + max(b[3] for b in last_line)) / 2
        else:
            name_right = None
        image = page.get_pixmap(matrix=fitz.Matrix(1.5, 1.5), alpha=False)
        red = []
        samples = image.samples
        for y in range(image.height):
            for x in range(image.width):
                at = y * image.stride + x * image.n
                if samples[at] > 170 and samples[at + 1] < 110 and samples[at + 2] < 110:
                    red.append((x / 1.5, y / 1.5))
        assert red, (case['file'], 'seal missing')
        left = min(p[0] for p in red)
        right = max(p[0] for p in red)
        top = min(p[1] for p in red)
        bottom = max(p[1] for p in red)
        if name_right is not None:
            if len(expected_name) > 1:
                assert abs((left + right) / 2 - name_right) < 4, (case['file'], 'not on name right edge', left, right, name_right)
            assert left < name_right < right, (case['file'], 'name end not overlapped')
            assert abs((top + bottom) / 2 - name_middle) < 6, (case['file'], 'vertical alignment', top, bottom, name_middle)
        margin = 36 if case['kind'] == 'order' else 48
        limit = (page.rect.width - 16) / 2 if case['compact_order'] else page.rect.width - margin
        assert left >= margin - 1 and right <= limit + 1, (case['file'], 'outside party column', left, right, limit)
        assert top >= 0 and bottom <= page.rect.height, case['file']
        image.save(folder / (Path(case['file']).stem + '.png'))
        summary.append({'file': case['file'], 'name_right': name_right,
                        'seal_box': [left, top, right, bottom]})
(folder / 'visual-checks.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2))
print('PASS 22 real PDFs: saved representatives, generated/uploaded seal at name end, wrapped/newline/tiny/empty names, column bounds')
