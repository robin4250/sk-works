# 会社角印5種類：書体・利用許諾の再調査

確認日：2026-10-09 JST。アプリ確認基準 main `a2a0ad26cebfbcc39ec99fe49f8b78d4ceb6c202`。
この作業は読み取り監査のみ。フォント購入、契約、作者への連絡、アプリフォント/PDFコードの変更は行っていない。

## 結論

篆書系の商用・アプリ同梱可能な作者公開OFLフォントは見つかった。ただし日本の会社登録名を全文表現する字数が不足する。現時点で篆書・印相・古印・隷書・古印別配置の5種類を実装済みとは扱えない。無料ダウンロードまたは一般の商用利用許可だけで、アプリ内同梱と自動電子印影生成を許諾済みとは判断しない。

|候補|公式許諾確認|適合性/残り|
|---|---|---|
|JFZSKSealScript（敬峰中山王篆）|作者READMEと同梱OFL1.1全文、TTF name tableのOFL情報を確認。商用利用、ソフト同梱、埋込、生成文書可。著作権/全文保持、単独販売禁止、変更版のReserved Font Name注意。|本物の篆系で一般フォントの変形ではない。しかしV3にも「株・斉・隆・設・業」など欠字。日本の全会社名用の正式篆書として採用するには不十分。|
|LXGW Seal / 霞鹜篆书|作者公式READMEにOFL1.1、商用・アプリ同梱許可と全文添付条件を確認。|小篆の根拠を持つが現行READMEで75字。会社名用途に不足。|
|白舟 篆書/印相/古印/隷書|メーカー公式使用許諾は電子印影を素材・テンプレート用途とし別途連絡を指定、フォントファイルのソフト組込は別契約。無料版は一般利用1〜7の範囲限定。|通常購入・無料版をそのまま組み込めない。組込契約＋電子印影生成範囲の許諾未取得。|
|青柳隷書しも|公式配布ページとZIP内「フォントの使用方法」を確認。SIMO著作権、独自許諾。|公式ZIP同梱使用方法を取得。商用利用可、無料再配布可、使用方法と解説同梱必須、再配布有料不可、連絡不要。独自許諾でOFLではない。無料アプリ同梱候補。課金アプリ配布の再配布有料条件は未判断。|

## JFZSK 実ファイル検査

作者リポジトリ： https://github.com/SuperMate-Ai/JFZSKSealScript （旧 jeffi369 URLから転送）。
固定確認コミット：`a12bf04c0413da28e46cba3d16184ac91ad1bc96`。
`fontTools.ttLib.TTFont(...).getBestCmap()`で実TTFを検査。検査用の合成文字列は `株式会社有限会社合同会社斉藤隆一建設工業サービスSKO`。実会社登録データは外部に送信していない。

- V3 TTF mapped codepoints: 3060。欠字 `株斉隆設業サービスSKO`。
- V3 SHA256: `97b8ffdc5a715838a7be659aca626bfa4710ecd35e7eccb3ae2ffb2b7de2c250`。
- V2.5 mapped codepoints: 2717。同じ検査文字列の欠字はV3と同じ。
- V2.5 SHA256: `e83fb07014de89eed76dc2efb2305be6b52e011c46984e3bb9edfd82cb3924ee`。
- `chongxi_seal.otf` は別フォント。作者JFZSKのOFLをこのファイルへ自動適用せず、採用していない。

会社名の欠字をNoto等の通常書体で補って全体を「篆書」と表示しない。法人格を省略/旧字化して登録会社名を書き換える処理も行わない。

## 青柳隷書の実ファイル検査

公式配布ZIP： https://opentype.jp/bin/aoyagireisyosimo_ttf_2_01.zip

- ZIP SHA256: `3c4d62d669949dc2d5a9cd1cf0203b4c79d67c3a0760729af5163a0b0b58b1e7`。
- TTF SHA256: `a4c55ad5f72e65a482931d967725e97ff206eb3019c87281d9e5514a63bb8db9`。
- `aoyagireisyosimo_ttf_2_01.ttf` cmap: 14963 codepoints、上記合成会社名文字列の欠字なし。ただし全14963に独自の隷書glyphが存在することをこの数だけで保証せず、実帳票表示で確認する。
- ZIP同梱「フォントの使用方法.txt」（CP932）の作者独自条件を確認。利用と商用利用を許可、無料再配布許可、再配布の有料化は禁止、使用方法と解説を必ず同梱する。雑誌/本への掲載は連絡が必要だが、一般の使用/再配布は連絡不要。
- ZIPには「フォントの解説.doc」「フォントの解説.pdf」も存在する。実装採用する場合は元TTF・使用方法・解説を保持し、アプリから読めるようにする。作者ZIPの著作物をOFLと表記しない。
- 無料配布アプリでの同梱を有力候補とする。有料アプリ/課金プランでの再配布条件はこの読み取り結果だけで許諾済みとしない。今回フォントassetsへの追加は行っていない。

## 現行アプリ監査

`assets/fonts/company-seal/README.md` と `lib/features/shared/company_seal_pdf.dart` をmainで確認した。現在はOFLのNoto Sans JP Boldを登録会社名から三列に配置する共通角印。5書体選択は存在しない。Notoは合法的な現行共通角印の素材だが篆書ではなく、篆書と呼ばない。

## 次の実装条件

1. 任意の登録会社名に対する欠字を検出し、非対応を明示する。
2. 正式5種類それぞれの字体とアプリ同梱/自動印影生成の許諾を証跡付きで確保する。
3. 古印別配置は同じ許諾済み古印フォントの別配置として実装可能で、5つ全てが別フォントである必要はない。
4. 利用可能になった書体だけ、実Flutter PDFで生成・目視確認する。現行帳票の寸法とON/OFF仕様を維持する。

## 一次資料

- JFZSK 作者README： https://github.com/SuperMate-Ai/JFZSKSealScript
- JFZSK OFL全文： https://github.com/SuperMate-Ai/JFZSKSealScript/blob/a12bf04c0413da28e46cba3d16184ac91ad1bc96/OFL.txt
- LXGW作者README： https://github.com/lxgw/LxgwSeal/blob/main/README.md
- 白舟公式使用許諾： https://www.hakusyu.com/licensing.htm （特に無料版、8、電子印鑑、11）
- J-Font組込/サーバー契約案内： https://j-font.com/embed_license / https://j-font.com/server_license （検索結果確認、本ページ取得403のため契約条項を全文確認したとは扱わない）
- 青柳隷書公式配布： https://opentype.jp/aoyagireisho.htm
