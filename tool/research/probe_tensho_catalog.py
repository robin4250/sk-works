"""Metadata-first research: exact Unicode coverage within one CC BY-SA work.
Consumes downloaded official book-page HTML; never mixes works or substitutes glyphs.
No product/font output. Candidate counts do not establish style or glyph correctness.
"""
import argparse, hashlib, json, pathlib, re
p=argparse.ArgumentParser();p.add_argument('--pages',required=True);p.add_argument('--out',required=True);a=p.parse_args()
works={'印篆貫珠':[f'TE{i:05d}' for i in range(27,39)],'説文解字':['TE00039']}
names=['山川建設株式会社','青山土木株式会社','山川','𠮷山']
rows=[]
for work,ids in works.items():
    books=[]; total={}
    for book in ids:
        path=pathlib.Path(a.pages)/(book+'.html')
        if not path.exists():raise ValueError('Incomplete metadata: '+book)
        raw=path.read_bytes();s=raw.decode('utf-8');title=re.search(r'<title>(.*?)\s*\|',s).group(1)
        if title!=work:raise ValueError('Different work: '+book)
        cells = re.findall(r'<td id="U\+([0-9A-F]+)">(.*?)</td>', s, re.S)
        counts = {}
        for unicode, cell in cells:
            count = re.search(r'<div class="count">([0-9]+)</div>', cell)
            if not count:
                raise ValueError('Malformed Unicode cell: '+book)
            value = int(count.group(1))
            # Official page repeats the same catalog in frequency and Unicode order.
            if unicode in counts and counts[unicode] != value:
                raise ValueError('Inconsistent repeated Unicode count: '+book)
            counts[unicode] = value
        if not counts:raise ValueError('Empty Unicode catalog: '+book)
        for u,c in counts.items():total[u]=total.get(u,0)+c
        books.append({'id':book,'url':f'https://codh.rois.ac.jp/tensho/book/{book}/','html_sha256':hashlib.sha256(raw).hexdigest(),'character_count':len(counts),'target_counts':{f'U+{ord(c):04X}':counts.get(f'{ord(c):04X}',0) for c in dict.fromkeys('山川建設株式会社青土木𠮷會')}})
    rows.append({'work':work,'license':'CC BY-SA 4.0','license_source':'https://codh.rois.ac.jp/tensho/','books':books,'names':[{'name':name,'missing':[f'U+{ord(c):04X}' for c in dict.fromkeys(name) if not total.get(f'{ord(c):04X}',0)],'candidate_counts':{f'U+{ord(c):04X}':total.get(f'{ord(c):04X}',0) for c in dict.fromkeys(name)}} for name in names]})
overview = pathlib.Path(a.pages)/'overview.html'
if not overview.exists():
    raise ValueError('License source HTML missing')
pathlib.Path(a.out).write_text(json.dumps({'license_source_html_sha256':hashlib.sha256(overview.read_bytes()).hexdigest(),'credit':'篆書字体データセット（国文学研究資料館収集／CODH・DHII加工） doi:10.20676/00000390','research_only':True,'unicode_normalization':False,'style_classification':'not supplied by frequency catalog','works':rows},ensure_ascii=False,indent=2)+'\n')
for row in rows:print(row['work'],[(n['name'],n['missing']) for n in row['names']])
