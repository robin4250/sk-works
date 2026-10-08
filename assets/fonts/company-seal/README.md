# Company seal font

The company seal uses **Noto Sans JP Bold**, an offline bundled static weight-700 instance of the licensed Google Fonts Japanese font. This replaces the previously supplied brush lettering at the user's request on 2026-10-08. Report geometry is unchanged.

The seal is generated from the registered company name in three vertical columns inside a red transparent square frame; no fixed company image or name is embedded.

## Source and reproducibility

- Upstream: https://github.com/google/fonts/tree/5e8a3ba899557829a76cfdac30fa512bda91d7ca/ofl/notosansjp
- Source file: `NotoSansJP[wght].ttf`
- Source SHA256: `c2f3b4d463500a2ddcd3849cded1fceeb9fd6d1c32e6cbecd568453ba50fc68f`
- Bundled static file: `NotoSansJP-Bold.ttf`
- Static file SHA256: `60aa355a4881177ce785dfa69a7951c563d0396c588d24d07bff9e8946e667a3`
- Conversion: fontTools `instantiateVariableFont(TTFont(source), {'wght': 700}, inplace=True)`, then save. No glyph subsetting, contours or company-specific changes.
- Reuse the pinned source download in `tool/prepare_pdf_fixture_font.py`, changing the static weight to 700.

## License

The original upstream copyright and SIL Open Font License 1.1 are preserved verbatim in `OFL.txt` and bundled with the font. The license permits commercial use, PDF embedding, modification and software redistribution. The font itself must not be sold separately and remains under OFL. The named reserved font name is `Source`; this static instance does not use that reserved name. Generated PDF documents are not subject to OFL.

Font byte loading is cached offline; each PDF receives an independent font wrapper. Rare characters absent from this font can use the document's Japanese fallback font.
