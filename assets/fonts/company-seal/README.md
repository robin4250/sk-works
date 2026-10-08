# Company seal font

The company seal uses **niseten by devizou**, an offline bundled seal-style font. The official author page currently links **CC0 1.0 / Public Domain**; preserve `niseten-source.txt` and `niseten-CC0-1.0.txt` with the unmodified TTF. Source: https://2ttf.com/HYPIvTKm8WE. Download: https://2ttf.com/webfont/HYPIvTKm8WE/webfont.ttf.

The registered name is rendered using each glyph's actual ink bounds, filling 92% of its vertical cell with red fill and a small red outline. The rounded frame, transparency and existing document placement/sizes remain unchanged. On 2026-10-08 the user changed direction from the generated B concept to an actual seal-script font. niseten is a small-seal-inspired typeface, not the geometric lettering of concept B. Actual Flutter PDF visual comparison is required before release.

The previously bundled **Noto Sans JP Bold** remains available with its original license and reproducibility information below; it is no longer the primary seal face.

The seal is generated from the registered company name in three vertical columns inside a red transparent square frame; no fixed company image or name is embedded.

## Retained Noto source and reproducibility

- Upstream: https://github.com/google/fonts/tree/5e8a3ba899557829a76cfdac30fa512bda91d7ca/ofl/notosansjp
- Source file: `NotoSansJP[wght].ttf`
- Source SHA256: `c2f3b4d463500a2ddcd3849cded1fceeb9fd6d1c32e6cbecd568453ba50fc68f`
- Bundled static file: `NotoSansJP-Bold.ttf`
- Static file SHA256: `60aa355a4881177ce785dfa69a7951c563d0396c588d24d07bff9e8946e667a3`
- Conversion: fontTools `instantiateVariableFont(TTFont(source), {'wght': 700}, inplace=True)`, then save. No glyph subsetting, contours or company-specific changes.
- Reuse the pinned source download in `tool/prepare_pdf_fixture_font.py`, changing the static weight to 700.

## Retained Noto license

The original upstream copyright and SIL Open Font License 1.1 are preserved verbatim in `OFL.txt` and bundled with the font. The license permits commercial use, PDF embedding, modification and software redistribution. The font itself must not be sold separately and remains under OFL. The named reserved font name is `Source`; this static instance does not use that reserved name. Generated PDF documents are not subject to OFL.

Font byte loading is cached offline; each PDF receives an independent font wrapper. Rare characters absent from this font can use the document's Japanese fallback font.
