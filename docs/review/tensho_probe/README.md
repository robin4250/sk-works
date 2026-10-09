# 篆書の同一資料・完全一致Unicode probe

2026-10-09 JST。**研究用。製品の篆書実装・5書体完成ではない。**

## 原典と利用条件

CODH公式 [概要・資料別ライセンス](https://codh.rois.ac.jp/tensho/)、[新撰篆書字典](https://codh.rois.ac.jp/tensho/book/TE00024/)、[凡例](https://codh.rois.ac.jp/tensho/note/) を再取得。新撰篆書字典 TE00024–26 のみを選択し、CC BY-SA 4.0 の画像を使用する。CC BY-NC-SA の TE00040–58 は使わない。別資料の画像を混ぜない。

出典：『篆書字体データセット』（国文学研究資料館が複数の機関から収集／CODH・DHII加工） doi:10.20676/00000390。原本所蔵・公開：国立国会図書館。[CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)／[法的本文](https://creativecommons.org/licenses/by-sa/4.0/legalcode.ja)。派生画像 proof_0.png は同じ CC BY-SA 4.0 で提供する。配布物に公式 provider.ja.txt を含める。画像の改変は等比縮小・配置・赤枠追加のみ。元スキャンの紙色・汚れは残し、筆画修復、描き足し、閾値処理、font変形は行っていない。コードは既存リポジトリの扱いに従うが、画像のライセンスを変えない。

本probeは商用利用可能な画像の利用方法を検証するもの。アプリ同梱時の帰属表示・生成物への継承・第三者再配布条件・利用者への案内は製品採用時に具体化する。ソフトウェア全体の条件に関する法的判断をこのprobeだけで確定しない。

## 取得・変換の証拠

coverage.json に公式ZIPのURL・取得サイズ・SHA256と、文字ごとの全候補メンバー名を保存。composition/manifest.json に選択した元画像のSHA256、原本のページ・座標・IIIF manifest/canvas/image URLを保持。画像はUnicode完全一致で検索する。Unicode正規化や旧字置換はしない。画像候補が複数ある場合は明示 selection.json が必須。最初のファイルを正解と推測しない。

原ZIPは大きいため同梱しない。元切り出し2枚と合成proofだけを保持する。ダウンロード先は公式配布URLであり、取得hashを再現の基準にする（公式署名や公式hashがあったという意味ではない）。

## 結果と採用できない理由

| 合成名 | 同一資料の完全一致coverage | 複数候補 |
|---|---|---|
| 山川建設株式会社 | 会 U+4F1A がない | 山・川・建・社 |
| 青山土木株式会社 | 会 U+4F1A がない | 青・山・土・木・社 |
| 山川 | 2字とも存在 | 山4枚・川2枚 |
| 𠮷山 | 𠮷 U+20BB7 がない | 山 |

「会」を「會」に置換すると登録会社名を勝手に変更するため拒否する。異体字や通用仮借を含み得る資料のUnicodeラベルだけで、現代会社名の正確な篆書字形を証明できない。

山川2字proofは画像を機械的に配置できるという証拠。候補画像を目視した上で選択したが、同一作品にも異なる字形があり、coordinate.csv/source.csvに書体分類列はない。**同じstyleの全字形を確保した証拠ではない。** 原本ページと字形の専門的な同定、会社名全文のcoverage、紙色除去と筆画の欠損検査、実寸印刷の可読性が残る。研究proofを会社角印として提供しない。

## 再現

Python標準ライブラリでcoverage、Pillowで画像配置。全ZIPを外部cacheへ取得し、以下を実行する。

```sh
python tool/research/probe_tensho_dataset.py \
  --zip /tmp/sko-tensho-probe/TE00024.zip \
  --zip /tmp/sko-tensho-probe/TE00025.zip \
  --zip /tmp/sko-tensho-probe/TE00026.zip \
  --name 山川建設株式会社 --name 青山土木株式会社 --name 山川 --name 𠮷山 \
  --out /tmp/sko-tensho-probe/coverage
python tool/research/probe_tensho_dataset.py \
  --zip /tmp/sko-tensho-probe/TE00024.zip \
  --zip /tmp/sko-tensho-probe/TE00025.zip \
  --zip /tmp/sko-tensho-probe/TE00026.zip \
  --name 山川 --selection docs/review/tensho_probe/selection.json \
  --out /tmp/sko-tensho-probe/composition
```

実行結果：coverage全4例、明示選択による2字PNG生成成功。欠字例にselectionを渡した場合は例外で生成停止。NC/未承認資料IDを拒否。ローカルFlutterは未実行。製品 lib/shared/assets/DB/Auth の変更なし。
