"""Read actual synthetic Dart-generated PDFs; never connect to production."""
from pathlib import Path
import sys
import re
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
        total_label = 'ご請求金額（税込）' if kind == 'invoice' else '支払金額'
        assert re.search(re.escape(total_label) + r'\s*¥' + re.escape(amount), first), (kind, mode)
        assert '別途経費合計：1234円' in details, (kind, mode)
        # The fixture claim ID is internal; retain the human-readable audit row.
        assert 'charged' not in first + details and '申請ID' not in details, (kind, mode)
        assert '2026/10/1' in details and '試験 太郎' in details, (kind, mode)
        assert '検証交通費' in details and '承認済み' in details, (kind, mode)
        assert ('取引先' if kind == 'invoice' else '下請け・協力会社') in details, (kind, mode)
        assert details.count('1234円') == 2, (kind, mode)  # detail row + declared total
        assert '税・福利厚生費の加算対象外' in details, (kind, mode)
        if mode == 'only':
            body = first.replace('工事代金支払明細書', '')
            assert '工事代金' not in body and '通常作業' not in body, (kind, mode)
        else:
            assert '通常作業' in first and '20,000' in first, (kind, mode)
            # The adopted layout lists expense in subtotal and welfare separately.
            tax_label = '消費税（10%）' if kind == 'invoice' else '消費税'
            for label, value in (('小計', '21,234'), ('福利厚生費', '1,600'), (tax_label, '2,160')):
                assert re.search(re.escape(label) + r'\s+' + re.escape(value), first), (kind, mode, label)
        print(f'PASS {kind}/{mode}: original expense in total and page-two charged detail')
        with fitz.open(root / f'{kind}_{mode}.pdf') as document:
            for index, page in enumerate(document):
                page.get_pixmap(dpi=120).save(root / f'{kind}_{mode}_page_{index + 1}.png')
