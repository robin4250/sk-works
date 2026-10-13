# Adopted PDF comparison: 84b2002

Status: **comparison performed; not complete or approved for installation**.

Actual Flutter-generated files came from GitHub Actions run `37696639004`, artifact `11514634935`. The ZIP was downloaded through the GitHub connector and extracted without modifying its PDFs. The five generated PDFs are preserved in `generated/84b2002/`.

Reference masters are `invoice_adopted_seal_overlap_lower_v8.pdf` and `payroll_soft_equal_width_more_rows_v4.pdf`. Comparison used PyMuPDF text/vector extraction and rendered images at 1.5×. The masters use unembedded `HeiseiKakuGo-W5`; Poppler on this host omitted Japanese glyphs, so its incomplete rendering was not used as evidence of a source defect.

## Verified geometry

Both reference masters and the principal generated fixtures have one A4 portrait page, `595.2756 × 841.8898 pt`.

| Area | Master and generated coordinates, in points |
| --- | --- |
| Invoice outer frame | `(16, 16)–(579.28, 825.89)` |
| Invoice customer block | `(28, 80)–(294, 176)` |
| Invoice amount block | `(316, 80)–(567.28, 135)` |
| Invoice bank block | `(316, 143)–(567.28, 231)` |
| Invoice detail table | `(28, 244)–(567.28, 669.89)`; 35 numbered detail rows |
| Invoice bottom company/approval area | `(28, 744.89)–(567.28, 814.89)` |
| Payroll earnings panel | `(38, 270)–(292.64, 575)` |
| Payroll deduction panel | `(302.64, 270)–(557.28, 575)`; same width as earnings |
| Payroll net-payment area | `(38, 584)–(557.28, 663)` |
| Payroll three independent amount boxes | y `617–656`; x `48–198.43`, `222.43–372.85`, `396.85–547.28` |
| Payroll notes/bank boxes | y `749.89–806.89`; x `38–338`, `348–557.28` |

The blue earnings, red deductions and green net amount, independent rounded amount boxes, external minus/equal signs and lower notes/bank placement are retained. Fixture values agree: invoice total `1,210,000`; payroll earnings `408,248`, deductions `95,600`, net `312,648`.

## Remaining differences in this artifact

| Item | Adopted master | Generated 84b2002 |
| --- | --- | --- |
| Invoice title | `請　求　書`, 20 pt, width 100 pt | `請求書`, 20 pt, extracted width about 69 pt |
| Payroll title | `給 与 明 細 書`, 19 pt | `給与明細書`, 18 pt |
| Payroll company text bounding box | y `54.27–64.27` | y `47–61.48` |
| Payroll payment-month text | 12.5 pt | 12 pt |
| Payroll mode banner | `月 給 例`, 16 pt; subtitle 8.5 pt at x 138 | `月給`, 15 pt; subtitle 7 pt at x 96 |
| Payroll profile cells | Master cell placement | Unequal cell widths/positions differ; e.g. affiliation text x 216 versus x 267.55 |
| Payroll paid-leave label | `有給取得` | `有給` |
| Payroll earnings header | `2　●　支給（＋）` | `2 支給（＋）` |
| Japanese font metrics | `HeiseiKakuGo-W5` | Embedded font internally identified as `NotoSansJP-Thin`; different glyph metrics and baseline boxes |
| Company seal | Adopted traditional seal lettering, stroke shape and frame | Ordinary red typeset characters inside a square; does not match adopted `IMG_0367.png` |
| Invoice approval fixture | Master has two named/date-bearing sample stamps | Generated fixture has empty circles; this fixture does not verify approved-stamp rendering or lifecycle |

Font names reported by PDF extraction alone do not establish the selected visual weight of a variable font. The visible text spacing, font sizes and baseline differences require further correction/comparison.

## Scope and limits

The pagination fixture has two A4 pages; the many-row payroll fixture has three A4 pages. Their files are preserved, but this report does not certify all overflow content, registered production-data mapping, approval persistence, cancellation/reapproval, company-specific stamp-date settings, printing/sharing or device behavior. CI success is not treated as design completion. Later fixes must generate a fresh artifact and receive a new comparison; this report records the immutable 84b2002 output only.
