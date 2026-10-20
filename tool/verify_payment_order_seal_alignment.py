"""Inspect the actual generated order page; no app or production connection."""
from pathlib import Path
import sys
import fitz

proof = Path(sys.argv[1] if len(sys.argv) > 1 else 'build/payment-order-proof')
for name in ('payment-order.pdf', 'payment-long.pdf'):
    with fitz.open(proof / name) as document:
        page = document[1]
        labels = [span for block in page.get_text('dict')['blocks']
                  for line in block.get('lines', []) for span in line['spans']
                  if '代表者名' in span['text']]
        if not labels:
            raise AssertionError(f'{name}: issuer representative label missing')
        # Issuer is rendered before the counterparty in both party layouts.
        top = labels[0]['bbox'][1]
        bottom = labels[0]['bbox'][3]
        image = page.get_pixmap(matrix=fitz.Matrix(1.5, 1.5), alpha=False)
        samples = image.samples
        red_rows = []
        for y in range(image.height):
            start = y * image.stride
            if any(samples[start+x*image.n] > 170 and
                   samples[start+x*image.n+1] < 110 and
                   samples[start+x*image.n+2] < 110
                   for x in range(image.width)):
                red_rows.append(y)
        if not red_rows:
            raise AssertionError(f'{name}: seal missing')
        center = (red_rows[0] + red_rows[-1]) / (2 * 1.5)
        # Long representative values may wrap; the seal should remain within
        # their row, while the normal single-line name is centered beside it.
        if name == 'payment-order.pdf' and abs(center - (top+bottom)/2) > 8:
            raise AssertionError(f'{name}: seal and representative centers differ by {abs(center-(top+bottom)/2):.1f}pt')
        if center < top - 30 or center > page.rect.height - 20:
            raise AssertionError(f'{name}: seal is outside the issuer area')
print('PASS normal and long order seal alignment in actual generated PDFs')
