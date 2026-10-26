"""Synthetic artifacts only; rendered header/footer regressions and line totals."""
from pathlib import Path
import sys,json
import fitz
root=Path(sys.argv[1]);checks=0
for kind in ('invoice','certificate'):
    base=fitz.open(root/f'{kind}_baseline.pdf');new=fitz.open(root/f'{kind}_adjusted.pdf')
    assert len(base)==len(new)==1
    text=new[0].get_text()
    for expected in ('追加支給','材料控除','追加税なし','11,850','500','-200'):
        assert expected in text,(kind,expected)
        checks+=1
    # The invoice's two printed total boxes must change. The adopted issuer,
    # address, footer and title regions must remain pixel-identical.
    clips=[fitz.Rect(0,0,300,230),fitz.Rect(0,744,595,842)] if kind=='invoice' else [fitz.Rect(0,0,595,145),fitz.Rect(0,800,595,842)]
    for i,clip in enumerate(clips):
        before=base[0].get_pixmap(matrix=fitz.Matrix(2,2),clip=clip,alpha=False)
        after=new[0].get_pixmap(matrix=fitz.Matrix(2,2),clip=clip,alpha=False)
        assert before.samples==after.samples,(kind,'adopted frame changed',i)
        checks+=1
    new[0].get_pixmap(matrix=fitz.Matrix(1.5,1.5),alpha=False).save(root/f'{kind}_adjusted.png')
    assert abs(new[0].rect.width-595.276)<.01 and abs(new[0].rect.height-841.890)<.01
    checks+=1
print(json.dumps({'checks':checks,'synthetic_only':True,'rendered':True}))
