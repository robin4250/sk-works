# SKO-028: current bundled seal fonts and Unicode boundaries

Read-only offline audit against main `de0470d616b480d98ee84ec47fb67ee4b5ea036e`, 2026-10-17. No new font download, purchase, external contact, seal save, live query, production change or device operation. This document records existing research separately from new observations; it does not complete the five-design requirement.

## Existing research preserved

Git ancestry and each PR's changed paths were checked before examining current assets. All six remain open Drafts and their exact heads are not ancestors of this main. Their absence from main history does not mean their research must be redone or their proposed changes should automatically be merged.

| PR / exact head | Existing result | Current-main comparison |
| --- | --- | --- |
| [#763](https://github.com/robin4250/sk-works/pull/763) `795cabc95480983f106678e8d3801ba9e2b85840` | Genuine-font licensing and Japanese coverage research | Its new license-audit document is absent; conclusions remain preserved in the Draft. No candidate font was fetched again. |
| [#808](https://github.com/robin4250/sk-works/pull/808) `5a73f853b74976d0d680ceb536025ac1854d0f4c` | Original Aoyagi font/terms and actual Flutter research PDFs, unsupported U+20BB7 refusal | Its nine research paths are absent. The current product Aoyagi asset has the exact same TTF SHA256 as the research fixture. Product integration already exists through other changes; do not re-add the research fixture as a new implementation. |
| [#817](https://github.com/robin4250/sk-works/pull/817) `9445d3fc1a737b16d736aabbc7356f62e0e415ed` | CC BY-SA image research; same-work exact Unicode coverage lacks 会 and 𠮷 in the tested work | Its nine research paths are absent. No dataset was downloaded or reprocessed. Image research is not a bundled font. |
| [#820](https://github.com/robin4250/sk-works/pull/820) `99bb074d55d885bf351d24ea0ebccb08f23fdd99` | Two further same-work metadata studies; 会 missing, with work-specific 𠮷 availability | Its four research paths are absent. Prior missing-character findings are not generalized across different works. |
| [#821](https://github.com/robin4250/sk-works/pull/821) `85fdcdcd86111c8b48bf7b276db30574a73055c9` | Historical purchase routes and unresolved SKO-specific permissions | Its new document is absent. Prices and terms were not refreshed; no quote, permission, purchase or contract is inferred. |
| [#823](https://github.com/robin4250/sk-works/pull/823) `faedf42f959c5cd793646b5469a4d4dc66e6484d` | Canonical-ledger correction and subsequent limited production-application report | The preflight path exists, but its blob differs: this main lacks the head's correction/report (92 additions/15 deletions versus the original). The Draft's later report must not be replaced by the older document's absence observation. No migration, calculation or live preflight is repeated here. |

The existing `company_seal_reisho_phase1_20261009.md`, `company_seal_document_snapshots_20261009.md`, `company_seal_license_followup_20261009.md`, and `company_seal_remaining_font_acceptance_20261009.md` already describe the implemented Reisho path and remaining licenses. This audit adds exact current-asset and Unicode-boundary evidence rather than another font search.

## Exact current assets

Python fontTools **4.61.1** `TTFont.getBestCmap()` and all Unicode cmap subtables were examined locally. Both best-cmap sets equal the union of Unicode scalar mappings. Neither set maps a scalar to `.notdef`. These properties establish mappings, not genuine style or readable printed outlines for every mapped glyph.

| Bundled asset | SHA256 | Scalar cmap size | `OS/2.usWeightClass` | `OS/2.fsType` |
| --- | --- | ---: | ---: | ---: |
| `assets/fonts/company-seal/NotoSansJP-Bold.ttf` | `60aa355a4881177ce785dfa69a7951c563d0396c588d24d07bff9e8946e667a3` | 16732 | 700 | 0 |
| `assets/fonts/company-seal/aoyagi-reisho/AoyagiReisho.ttf` | `a4c55ad5f72e65a482931d967725e97ff206eb3019c87281d9e5514a63bb8db9` | 14963 | 400 | 8 |

The Aoyagi `coverage.json` is exactly the sorted current best cmap: 14963 entries, no stale/extra/missing scalar entries. Its cmap formats are 0 and 4; it has no format-14 variation-sequence table. Noto has formats 4/12/14/6/4/12. Noto's family-name metadata still says “Noto Sans JP Thin”, but its measured weight class is 700 and bytes match the documented static instance; the family string is not proof that a different weight was bundled.

## New synthetic Unicode boundary observations

No real registered company name was read or sent anywhere. Existing common-name/old-kanji results were retained as controls; decomposed kana and variation sequences extend the previous coverage evidence.

| Synthetic input | Current Aoyagi result | Noto observation |
| --- | --- | --- |
| `山川建設株式会社` / `青山土木株式会社` | All scalar mappings present | All scalar mappings present |
| `株式会社髙﨑𠮷野` | U+20BB7 𠮷 absent; 髙/﨑 present | All scalar mappings present |
| `合同会社ABC１２３` | All scalar mappings present | All scalar mappings present |
| `株式会社が` (precomposed U+304C) | All scalar mappings present | All scalar mappings present |
| `株式会社が` (U+304B + U+3099) | Combining U+3099 absent | Both scalars mapped; shaping/rendering not tested |
| `株式会社辻` followed by U+E0100 | Variation selector absent; no format-14 table | Format-14 maps the exact 辻/U+E0100 sequence to `glyph16335`; absence of the selector from best cmap alone is **not** a missing-sequence conclusion |

`CompanySealPdf.unsupportedReishoCharacters` checks original runes against that frozen scalar set. `_buildReisho` repeats coverage/length/glyph-size checks and renders one rune per cell without a normal-font fallback. Thus the decomposed-kana and IVS inputs above are currently rejected, not silently normalized, stripped or replaced. This is an offline source/cmap conclusion, not a new Flutter/PDF/device test. Visual equivalence is not Unicode identity. Any future normalization or IVS support needs an explicit registered-name preservation contract and actual shaping/PDF tests; do not remove selectors or change kana automatically to make coverage pass.

## Bundled permission evidence and remaining work

Noto's existing `OFL.txt` retains the original copyright and SIL OFL 1.1; its README records the pinned source and static-instance conversion. Noto remains the legacy ordinary typeface, not a genuine Tensho substitute. No license text was replaced.

Aoyagi is under the bundled author's independent terms, **not OFL**. Decoding `FONT-USAGE-original-cp932.txt` as CP932 yields exactly `FONT-USAGE-utf8.txt` as UTF-8, including original line endings. Original usage text and explanation PDF/DOC are present and the font hash matches #808. The retained terms allow commercial use and free redistribution, prohibit charging for redistribution, and require usage/explanation documents. Existing free-internal-trial interpretation is retained; no new permission for paid app/feature distribution is established. Font embedding metadata is recorded above but cannot grant or enlarge a license.

Current settings support legacy, genuine Reisho, and three immutable company-bound PNG variants when authorized for that fixed company. Three PNG variants plus legacy and Reisho may produce five menu choices, but do not implement the requested genuine Tensho/Inso/Koin/Reisho/Koin-alternative-layout set. Fixed PNGs are not fonts and cannot generate arbitrary registered company names.

Remaining: genuine Tensho/Inso/Koin assets and SKO-specific distribution/output permissions; Koin's second layout; paid-distribution resolution for Reisho; accepted full-name Unicode coverage and legibility; actual five-design Flutter PDF comparison and Release-device verification. Keep historical research and current snapshots, ON/OFF, financial calculations, company settings and roles unchanged. No source/asset/SQL implementation or production operation is authorized by this audit.

Validation: exact hashes, best/union cmap comparison, frozen-coverage equality, `.notdef` mapping absence, format-14 sequence inspection, font metadata and original/UTF-8 usage-text equality were measured offline. Git compared all six exact heads/changed-path sets before the audit. No existing PDF research was regenerated and no font or dataset was fetched.
