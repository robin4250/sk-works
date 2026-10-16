"""Inspect real PDF text and exact rendered pixels; no source-string assertions."""
import hashlib
import json
import pathlib
import sys
import fitz

root = pathlib.Path(sys.argv[1])
report = {}
for family in ('month', 'workers'):
    expected = None
    for phase in ('before', 'renamed', 'retired'):
        pdf = fitz.open(root / f'attendance_units_{family}_{phase}.pdf')
        assert len(pdf) == 1
        text = ''.join(page.get_text() for page in pdf)
        compact = ''.join(text.split())
        for token in ('足場手当1組', '安全手当1本'):
            assert compact.count(token) == 2, (family, phase, token, compact)
        assert '足場手当1回' not in compact and '安全手当1回' not in compact
        pix = pdf[0].get_pixmap(matrix=fitz.Matrix(1.5, 1.5), alpha=False)
        digest = hashlib.sha256(pix.samples).hexdigest()
        if expected is None:
            expected = digest
            pix.save(root / f'attendance_units_{family}_before.png')
        assert digest == expected, (family, phase, 'render changed')
        report[f'{family}_{phase}'] = {'pages': len(pdf), 'pixel_sha256': digest,
                                      'width': pix.width, 'height': pix.height}
        pdf.close()
print(json.dumps(report, ensure_ascii=False))
