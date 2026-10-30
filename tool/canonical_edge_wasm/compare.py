"""Compare actual generated pages, not implementation text or mock bytes."""
import argparse,json,pathlib,fitz
p=pathlib.Path(__file__).resolve().parent
parser=argparse.ArgumentParser();parser.add_argument('--reference',type=pathlib.Path,required=True);a=parser.parse_args()
proof=[]
for case in ['order-v1','order-v2','acceptance-v1','acceptance-v2']:
 x=fitz.open(p/'build/out'/f'deno-{case}.pdf');y=fitz.open(a.reference/f'server-{case}.pdf');assert len(x)==len(y)==2
 for first,second in zip(x,y):
  assert abs(first.rect.width-595.28)<.1 and abs(first.rect.height-841.89)<.1
  assert first.get_text()==second.get_text()
  assert first.get_pixmap(matrix=fitz.Matrix(2,2)).samples==second.get_pixmap(matrix=fitz.Matrix(2,2)).samples
 proof.append({'case':case,'pages':2,'text_equal':True,'pixels_equal':True})
print(json.dumps(proof))
