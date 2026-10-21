"""Inspect the actual generated company-name seal overlay; no production access."""
from pathlib import Path
import sys
import fitz

proof = Path(sys.argv[1] if len(sys.argv) > 1 else 'build/payment-order-proof')
for name in ('payment-order.pdf', 'payment-long.pdf'):
    with fitz.open(proof / name) as document:
        page = document[1]
        spans = [s for b in page.get_text('dict')['blocks'] for l in b.get('lines', []) for s in l['spans']]
        names = [s for s in spans if '株式会社発注' in s['text'] and s.get('color', 0) == 0]
        if not names:
            raise AssertionError(f'{name}: issuer company name missing')
        name_box = names[0]['bbox']
        image = page.get_pixmap(matrix=fitz.Matrix(1.5, 1.5), alpha=False)
        samples = image.samples
        red_points = []
        for y in range(image.height):
            start = y * image.stride
            for x in range(image.width):
                at = start + x * image.n
                if samples[at] > 170 and samples[at+1] < 110 and samples[at+2] < 110:
                    red_points.append((x/1.5, y/1.5))
        if not red_points:
            raise AssertionError(f'{name}: seal missing')
        left=min(x for x,y in red_points);right=max(x for x,y in red_points)
        top=min(y for x,y in red_points);bottom=max(y for x,y in red_points)
        if min(right,name_box[2]) <= max(left,name_box[0]) or min(bottom,name_box[3]) <= max(top,name_box[1]):
            raise AssertionError(f'{name}: registered seal does not overlap issuer company name')
        if abs((top+bottom)/2-(name_box[1]+name_box[3])/2)>10:
            raise AssertionError(f'{name}: seal is not vertically aligned to issuer company name')
print('PASS normal and long order registered-seal overlay on issuer company name')
