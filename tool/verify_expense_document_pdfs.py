"""Check generated synthetic fixtures with pypdf; no production records."""
from pathlib import Path
from pypdf import PdfReader

root = Path('build/expense-documents-proof')
for kind in ['payroll', 'invoice', 'payment']:
    original = PdfReader(root / f'{kind}_original.pdf')
    supplemented = PdfReader(root / f'{kind}_with.pdf')
    assert original.pages[0].extract_text() == supplemented.pages[0].extract_text(), kind
    detail = supplemented.pages[1].extract_text()
    assert '経費申請明細' in detail, kind
    if kind == 'payroll':
        assert len(original.pages) >= 2
        assert len(supplemented.pages) == len(original.pages) + 1
        assert original.pages[1].extract_text() == supplemented.pages[2].extract_text()
        for claim in ['APPROVED', 'PENDING', 'REJECTED']:
            assert claim in detail
    else:
        assert len(supplemented.pages) == 2
        assert ('APPROVED' if kind == 'invoice' else 'PENDING') in detail
        assert 'REJECTED' not in detail
    print(f'PASS {kind}: original first/continuation pages retained; details begin on page 2')
