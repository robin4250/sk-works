"""Read actual synthetic Dart-generated PDFs; never connect to production."""
from pathlib import Path
import sys
from pypdf import PdfReader
import fitz

root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('build/expense-cost-documents-proof')
for kind in ('invoice', 'payment'):
    for mode, amount in (('with_work', '24,994'), ('only', '1,234')):
        reader = PdfReader(root / f'{kind}_{mode}.pdf')
        assert len(reader.pages) == 2, (kind, mode)
        first = reader.pages[0].extract_text()
        details = reader.pages[1].extract_text()
        assert '別途経費（原額）' in first, (kind, mode)
        assert amount in first, (kind, mode, first)
        assert '別途経費合計：1234円' in details, (kind, mode)
        assert 'charged' in details and '検証交通費' in details, (kind, mode)
        assert '税・福利厚生費の加算対象外' in details, (kind, mode)
        if mode == 'only':
            body = first.replace('工事代金支払明細書', '')
            assert '工事代金' not in body and '通常作業' not in body, (kind, mode)
        elif kind == 'invoice':
            assert '21,600' in first and '2,160' in first, (kind, mode)
        print(f'PASS {kind}/{mode}: original expense in total and page-two charged detail')
        with fitz.open(root / f'{kind}_{mode}.pdf') as document:
            for index, page in enumerate(document):
                page.get_pixmap(dpi=120).save(root / f'{kind}_{mode}_page_{index + 1}.png')
