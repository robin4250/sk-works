"""Build a static Japanese test font from the checksum-pinned Google source."""
import hashlib
import pathlib
import urllib.request
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

ROOT = pathlib.Path('build/pdf-fixtures')
ROOT.mkdir(parents=True, exist_ok=True)
URL = 'https://raw.githubusercontent.com/google/fonts/5e8a3ba899557829a76cfdac30fa512bda91d7ca/ofl/notosansjp/NotoSansJP%5Bwght%5D.ttf'
EXPECTED = 'c2f3b4d463500a2ddcd3849cded1fceeb9fd6d1c32e6cbecd568453ba50fc68f'
data = urllib.request.urlopen(URL, timeout=60).read()
if hashlib.sha256(data).hexdigest() != EXPECTED:
    raise SystemExit('Japanese fixture font checksum mismatch')
source = ROOT / 'NotoSansJP-variable.ttf'
source.write_bytes(data)
font = instantiateVariableFont(TTFont(source), {'wght': 400}, inplace=True)
font.save(ROOT / 'NotoSansJP-Regular.ttf')
print('Verified Japanese PDF fixture font')
