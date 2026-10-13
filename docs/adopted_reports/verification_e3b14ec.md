# Actual PDF comparison: e3b14ec

Compared at `2026-10-07T23:07:29Z` (`2026-10-08 08:07 JST`). Source commit: `e3b14ec462db8f313f0fe7953153fc247d1afc48`. GitHub Actions run: `37699818179`; downloaded artifact: `11516862762`. The artifact's ten unmodified PDFs are preserved in `generated/e3b14ec/`.

This records actual generated output, not a claim of full completion, pixel identity or device installation. The run produced the PDFs despite one remaining source-contract test failure (692 passed, 1 failed, as reported by the integration lane); subsequent source fixes require their own successful CI confirmation.

## Method and metadata

Compared adopted `invoice_adopted_seal_overlap_lower_v8.pdf` and `payroll_soft_equal_width_more_rows_v4.pdf` using PyMuPDF vector/text extraction and 1.5× rendered page inspection. The reference Japanese font is unembedded `HeiseiKakuGo-W5`, so PyMuPDF's CJK fallback was used rather than this host's incomplete Poppler render. Rendered reference typography therefore has a substitution limitation.

Every generated page is A4 portrait, `595.2756 × 841.8898 pt`. The primary invoice and payroll each have one page; invoice pagination has two and payroll many-row output has three. All generated files report PDF 1.7, no encryption and empty author/creator/creation-date fields. No registration or approval timestamps were inferred from PDF metadata.

The primary reports embed body and shared seal fonts. Extracted font names and embedded subset byte lengths are:

| Report | Body font | Shared seal font |
| --- | --- | --- |
| Invoice | `NotoSansJP-Thin`, 33,608 bytes | `aoyagireisyosimo2`, 7,008 bytes |
| Payroll | `NotoSansJP-Thin`, 49,744 bytes | `aoyagireisyosimo2`, 7,008 bytes |
| Payment certificate, company 1 | `NotoSansJP-Thin`, 21,944 bytes | `aoyagireisyosimo2`, 7,008 bytes |

The body font's internal name does not by itself prove a selected variable-font visual weight.

## Verified layout and amounts

The principal invoice frame, customer, total, bank, 35-row detail table, notes and footer rectangles retain adopted coordinates. The invoice title is now a single line: 20 pt glyphs begin at x `247.64`, `287.64`, `327.64`, matching the adopted title's three character positions. The earlier title/subtitle overlap is absent.

Payroll retains the adopted A4 frame, equal-width earnings/deduction panels, work-results panel, independent blue/red/green amount boxes, minus/equal signs outside the boxes, and lower notes/bank boxes. The title is 19 pt, payment month 12.5 pt, banner 16 pt, and banner subtitle 8.5 pt at adopted x `138`. Employee affiliation x `216` and salary-type x `395` match the master. `有給取得`, individual hours/days, earnings calculation descriptions and deductions remarks appear in actual output. The earnings header again includes the white circular marker.

| Actual fixture | Verified values |
| --- | --- |
| Invoice | subtotal `1,100,000`, tax `110,000`, grand total `1,210,000` |
| Payroll | earnings `408,248`, deductions `95,600`, net `312,648` |
| Both payment certificates | work lines `500,000` and `25,000`; gross `525,000`; deduction `-25,000`; net `¥500,000` |

## Shared seal and approval fixtures

The three report types use red Japanese lettering, transparent interiors and rounded square frames. Company 1 (`すみだ建設株式会社`) and company 2 (`株式会社青空工業`) show different generated lettering; all name characters are present. The invoice/payment fixtures visibly use the embedded shared font, and payroll now does too.

All three principal report types now overlap the right end of the registered payer company name slightly:

| Report | Company text end x | Seal left x | Overlap |
| --- | --- | --- | --- |
| Invoice | `242.00` | `230.14` | about `11.86 pt` |
| Payroll | `128.00` | `124.00` | `4 pt` |
| Payment certificate 1 | `432.26` | `428.26` | `4 pt` |

The red lettering/frame remain visually different from the supplied `IMG_0367.png`: the generated font is calligraphic rather than the reference's dense, rectilinear seal script. This implements a similar dynamic seal rather than a pixel reproduction of a fixed company image; acceptance depends on the user's authorized similarity allowance.

The approved invoice fixture contains confirmation `斉藤` with manual display date `2026.09.30`, approval `山田` with no display date, and approval `鈴木` with `2026.10.08`. The pending fixture has no person stamps. The missing-date fixture displays approval `佐藤` without inventing a date. These establish generated PDF behavior only, not production persistence or RLS behavior.

## Remaining visible differences and limits

- Japanese body font metrics differ from the unembedded master font. For example payroll company text has extracted bounding box y `54–68.48`, versus master y `54.27–64.27`; the payroll title bounds are y `60.24–87.76`, versus master `63.32–82.32`. Extraction boxes are not identical to painted glyph outlines.
- Payroll's real salary-mode label is `月給`, while the master demo says `月 給 例`. This semantic fixture difference remains; it is not evidence of amount loss.
- Some payroll totals/table text baseline metrics and spacing differ from the master, though enclosing rectangles and verified values are retained. The notes wrapping also follows the embedded font rather than the reference's line segmentation.
- Payment certificate seal overlap increases its header height compared with the previous separated-seal fixture and moves the table downward. No adopted payment-certificate PDF was supplied for a strict geometry comparison in this check.
- No new title collision, page-edge clipping or seal glyph truncation was seen in the inspected principal page renders. Overflow files were generated and preserved, but their complete content is not certified here.
- Production data mapping, company settings, approval cancellation/reapproval/history, same-byte preview/print/share behavior, physical printing and iPhone Release installation still need their respective checks. This artifact comparison does not replace them or a successful final CI run.
