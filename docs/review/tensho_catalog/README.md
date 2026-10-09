# 篆書の残る2資料：metadata先行coverage比較

2026-10-09 JST。研究のみ。製品の篆書体・印相体・古印体や5書体の完成ではない。

[CODH公式概要・資料別条件](https://codh.rois.ac.jp/tensho/)で、国立国会図書館所蔵『印篆貫珠』TE00027–38、京都大学人文科学研究所所蔵『説文解字』TE00039 が CC BY-SA 4.0 対象であることを確認した。各資料の公式book HTML全13ページのUnicode頻度表を取得し、同一作品内でのみ候補数を合算。原HTMLの SHA256 とURL、資料ごとの候補数を coverage.json に保持する。二つの並び順の表を重複加算せず、一致しない重複は停止する。Unicode正規化・旧字置換・作品間の合算をしない。

| 合成名 | 印篆貫珠（12巻） | 説文解字（1資料） |
|---|---|---|
| 山川建設株式会社 | 株・会・社が欠字 | 会が欠字 |
| 青山土木株式会社 | 株・会・社が欠字 | 青・会が欠字 |
| 山川 | 山94候補、川14候補 | 山1候補、川1候補 |
| 𠮷山 | 𠮷2候補、山94候補 | 𠮷が欠字 |

「会」は U+4F1A の完全一致。會 U+6703 などへの置換は登録名を変えるため行わない。前の新撰篆書字典probeで「𠮷」が欠字だった事実は、その作品に限定する。印篆貫珠 TE00028 には U+20BB7 の2候補があり、[公式Unicodeページ](https://codh.rois.ac.jp/tensho/unicode/U+20BB7/)でも照合できた。

**この結果で会社名全文の篆書提供へは進めない。** 頻度表は画像候補のラベルを示すだけで、候補字形の現代文字としての正しさ、同一style、筆画欠損、実寸可読性を保証しない。TE00039 の大ZIP（公式表示約126MB）や全資料ZIPは、対象会社名で既に欠字が判明したため取得していない。画像のダウンロード・選択・変換・製品同梱・実Flutter PDF生成はこの比較では行っていない。

出典：『篆書字体データセット』（国文学研究資料館が複数の機関から収集／CODH・DHII加工） doi:10.20676/00000390。配布される比較メタデータ coverage.json は [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/) として提供する（改変：各作品の対象文字候補数を抽出・合算）。元画像は含まない。画像・ソフトウェアを製品採用する場合は、CODH指定の原本画像公開元・所蔵者一覧の同梱、帰属、生成物の継承条件を具体化する。アプリ全体のライセンスへの影響は、このmetadata比較では法的に確定しない。

## 再現

公式ページを外部cacheへ取得し、Python標準ライブラリで比較する。

```sh
python3 - <<'PY'
import pathlib, urllib.request
p = pathlib.Path('/tmp/sko-tensho-followup/pages')
p.mkdir(parents=True, exist_ok=True)
for i in range(27, 40):
    book = f'TE{i:05d}'
    url = f'https://codh.rois.ac.jp/tensho/book/{book}/'
    (p / (book + '.html')).write_bytes(urllib.request.urlopen(url, timeout=30).read())
(p / 'overview.html').write_bytes(urllib.request.urlopen('https://codh.rois.ac.jp/tensho/', timeout=30).read())
PY
python3 tool/research/probe_tensho_catalog.py \
  --pages /tmp/sko-tensho-followup/pages \
  --out /tmp/sko-tensho-followup/coverage.json
```

HTMLは変わり得るため取得hashも比較する。公式署名/hashが公開されていたという意味ではない。全13資料がない、作品名が違う、Unicodeセルが壊れている、同一セルの候補数が一致しない場合は停止する。ローカル実行で上表4名×2作品の結果を確認済み。ローカルFlutterは未実行。製品 lib/assets/DB/Auth、登録済みデータの変更なし。
