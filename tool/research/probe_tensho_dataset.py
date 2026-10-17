"""Research only: exact Unicode coverage and explicit reviewed glyph composition.
No automatic variant choice, Unicode normalization, glyph substitution or font fallback.
Requires Pillow only when --selection is provided. Source ZIPs stay outside the repo.
"""
import argparse, csv, hashlib, io, json, pathlib, zipfile

ALLOWED = {'TE00024', 'TE00025', 'TE00026'}  # One work, CC BY-SA only.
CREDIT = '篆書字体データセット（国文学研究資料館収集／CODH・DHII加工） doi:10.20676/00000390'
p = argparse.ArgumentParser()
p.add_argument('--zip', action='append', required=True)
p.add_argument('--name', action='append', required=True)
p.add_argument('--out', required=True)
p.add_argument('--selection', help='Explicit Unicode-to-original-ZIP-member JSON; no first-file guess')
a = p.parse_args()
out = pathlib.Path(a.out); out.mkdir(parents=True, exist_ok=True)
index, archives, sources, coordinates, archive_records = {}, {}, {}, {}, []
for path in a.zip:
    raw = pathlib.Path(path).read_bytes(); z = zipfile.ZipFile(io.BytesIO(raw))
    book = pathlib.Path(path).stem
    if book not in ALLOWED: raise ValueError('Unreviewed or NC corpus rejected')
    archives[book] = z
    archive_records.append({'dataset': book, 'url': f'https://codh.rois.ac.jp/tensho/dataset/v2/{book}.zip', 'sha256': hashlib.sha256(raw).hexdigest(), 'bytes': len(raw)})
    sources[book] = {r['Image']: r for r in csv.DictReader(io.StringIO(z.read(f'{book}/{book}_source.csv').decode('utf-8-sig')))}
    coordinates[book] = list(csv.DictReader(io.StringIO(z.read(f'{book}/{book}_coordinate.csv').decode('utf-8-sig'))))
    for member in z.namelist():
        parts = member.split('/')
        if len(parts) == 4 and parts[1] == 'characters' and member.endswith('.jpg'):
            index.setdefault(parts[2], []).append(member)
report = {'research_only': True, 'work': '新撰篆書字典', 'license': 'CC BY-SA 4.0', 'license_url': 'https://creativecommons.org/licenses/by-sa/4.0/', 'credit': CREDIT, 'archives': archive_records, 'names': []}
for name in a.name:
    candidates = {f'U+{ord(c):04X}': sorted(index.get(f'U+{ord(c):04X}', [])) for c in dict.fromkeys(name)}
    report['names'].append({'name': name, 'candidates': candidates, 'missing': [k for k, v in candidates.items() if not v], 'ambiguous': [k for k, v in candidates.items() if len(v) > 1]})
if a.selection:
    from PIL import Image, ImageOps, ImageDraw
    selection = json.loads(pathlib.Path(a.selection).read_text())
    for n, name in enumerate(a.name):
        glyphs, records = [], []
        for c in name:
            key = f'U+{ord(c):04X}'; member = selection.get(key)
            if member not in index.get(key, []): raise ValueError(f'Missing or unreviewed exact glyph: {key}')
            book = member.split('/')[0]; raw = archives[book].read(member)
            stem = pathlib.Path(member).stem; image_id = stem.split('_X')[0].split('_', 1)[1]
            xy = stem.split('_X')[1]; x, y = map(int, xy.split('_Y'))
            rows = [r for r in coordinates[book] if r['Unicode'] == key and r['Image'] == image_id and int(r['X']) == x and int(r['Y']) == y]
            if len(rows) != 1: raise ValueError('Ambiguous source coordinates')
            source_path = out / pathlib.Path(member).name; source_path.write_bytes(raw)
            glyph = Image.open(io.BytesIO(raw)).convert('L')
            # Isotropic resize of the whole source crop; no redraw/threshold/denoise.
            glyphs.append(ImageOps.contain(glyph, (190, 190)))
            records.append({'character': c, 'unicode': key, 'member': member, 'sha256': hashlib.sha256(raw).hexdigest(), 'coordinate': rows[0], 'source': sources[book][image_id]})
        size = 660; canvas = Image.new('RGB', (size, size), 'white'); draw = ImageDraw.Draw(canvas)
        draw.rectangle((8, 8, size-9, size-9), outline=(200,0,0), width=5)
        for i, glyph in enumerate(glyphs):
            # 3 rows, columns right-to-left; source scan remains greyscale.
            col, row = 2-i//3, i%3
            canvas.paste(glyph, (30+col*210+(190-glyph.width)//2, 30+row*210+(190-glyph.height)//2))
        if len(glyphs) > 9: raise ValueError('Research layout is limited to nine glyphs')
        canvas.save(out/f'proof_{n}.png')
        report['names'][n]['selected_glyphs'] = records
        report['names'][n]['changes'] = 'Original scan crops isotropically resized and arranged in a research square; red border added. No stroke reconstruction. Not a product seal.'
(out/'manifest.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n')
print(json.dumps({'archives': archive_records, 'names': [{'name': n['name'], 'missing': n['missing'], 'ambiguous': n['ambiguous']} for n in report['names']]}, ensure_ascii=False))
