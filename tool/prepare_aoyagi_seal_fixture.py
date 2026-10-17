"""Inspect the unmodified official font; never supply fallback glyphs."""
import hashlib
import json
from pathlib import Path
from fontTools.ttLib import TTFont

source = Path("test/fixtures/aoyagi-reisho/AoyagiReisho.ttf")
assert hashlib.sha256(source.read_bytes()).hexdigest() == "a4c55ad5f72e65a482931d967725e97ff206eb3019c87281d9e5514a63bb8db9"
cmap = TTFont(source).getBestCmap()
assert len(cmap) == 14963
names = ["株式会社テスト建設", "有限会社テストサービス", "合同会社長い会社名建設工業サービスSKO", "株式会社髙﨑齋藤神田𠮷野"]
results = [{"name": name, "missing": "".join(ch for ch in name if ord(ch) not in cmap)} for name in names]
assert all(not entry["missing"] for entry in results[:3])
assert results[3]["missing"] == "𠮷"
output = Path("build/aoyagi-seal-fixture")
output.mkdir(parents=True, exist_ok=True)
(output / "coverage.json").write_text(json.dumps({"cmapCount": len(cmap), "codepoints": sorted(cmap), "samples": results}, ensure_ascii=False), encoding="utf-8")
print(json.dumps(results, ensure_ascii=False))
