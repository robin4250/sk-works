# 支払経費v2：実generator・確定・詳細読取へ接続するSQL候補

`3b8669f2`の読取adapter候補を継承し、次の具体差分をreview-only SQLと隔離検証へ保存した。製品migrationや本番DBへ適用していない。

## 変更する実関数

1. `private.refresh_automatic_payment_certificate(uuid,uuid,date)`：新規の自動draftのみ、既定OFFのprivate gateが有効な場合に経費をgrossへ加えずdeductionsへ入れ、net=gross−deductionsを保存する。工事なし・経費1,000円はgross0／deductions1,000／net−1,000。同じid/revisionをsnapshotと独立basisへ結び付ける。既存v1draft/手編集/確定はv2へ暗黙変換しない。
2. `private.expense_cost_finalize()`：既存scope advisory lock・claim/choice row locks・cost_recovery purpose・消費PKをそのまま使い、v2の場合だけ同じ会社/帳票/相手/月/revisionの原額内訳を検査する。再利用される同じdocの消費記録も会社・document revision・claim revision・原額が一致しなければ拒否。既v1/invoice分岐は維持する。
3. `private.read_expense_document(text,uuid)`：既存本人/会社/帳票権限判定を通った後だけ、v2の保存claim ID/revision/原額に該当する明細へ絞り、同じscope/versionのenvelopeとbasisを返す。旧v1応答は既存returnへ進み、新fieldを追加しない。

新しいprivate guardは、v2の同月完全期間・会社/相手/帳票/版・最小claim契約・計算行からのgross基礎・原額deductions・signed netを確認する。確定v2の更新/削除とv1へのdowngradeを拒否。新しい権限やpublic RPCは付与しない。

## 既存履歴と再実行

既v1の確定rowとexpense_amount_consumptionsをJSON全値で保護し、原額を負数へ変更しない。既v1draftも自動変換しない。新v2はexpense claimsの原額を1回だけcost_recoveryへ消費する。本人返金のpurpose reimbursementや給与consumerには触れない。

同一snapshotの再refreshではrevisionを増やさない。経費振分けの解除で金額0になったv2draftは同じidを保持し、envelope/basis/rowのrevisionを一度だけ揃える。新規の無関係・工事なし・経費なしの0円帳票を作らない。

## 実行した検証と限界

`setupExpenseCostFixture`と保存済み本来のmigration3本（原額cost、申請月、atomic review）を再利用してPGlite0.3.14へ実関数を作成し、この候補を適用した。実generator→保存row→live詳細→確定→frozen詳細→消費記録という経路を実行した。

- 経費のみ−1,000、cash/payroll/paidを問わず同じ費用負担方向。
- default OFFのv1維持、既v1確定row/ledger全値一致、旧draft非変換。
- 同snapshot再refreshのid/revision/総額不変、全振分け解除後の同ID0円と整合版。
- 確定時消費1件、同じ確認command再試行の元receipt一致、金額/振分け/精算変更拒否、確定v2更新/削除/downgrade拒否。
- 会社/相手/対象版/金額改ざん、保存されていないclaimでの確定、消費記録のdocument revision不一致の拒否とrollback。
- invoice原額加算と既invoice generator bodyの完全不変、非所属actorの既public詳細読取拒否。

固定原典の3関数hashをpreflightで検査する。これは隔離fixture由来のhashであり、最新本番bodyとの同等性を主張しない。変更原典/別schemaへ上書き適用しない。PGliteは合成helperと単一接続で、全実schema/RLS/JWT/native競合/trigger・削除保守全体は未証明。既存PostgreSQL競合検査の成功を今回の候補へ付け替えていない。

検証コマンド：`node tool/verify_expense_payment_direction_v2_candidate.mjs <existing-pglite-module-path>`。

## 実consumer接続前に必要なこと

- 現在のRecord/PDFはv1型だけ。新nested snapshotを無視する旧clientへv2を配信しないこと。private gateは常にfalseのまま保存し、対応client識別/能力契約と正式な適用承認を整える前に有効化しない。fixture内でのみ指定会社を有効化した。
- `PaymentCertificateRecord`へ方向を失わないunionを導入し、readerの会社・doc・period・revision・basisとPDF1枚目/明細を同時に接続する。SQLだけ反映、PDFの符号だけ反映のどちらも行わない。
- この原典generatorは従来からその他控除0を算出する。その既存仕様は変更せずbasisにも0を保持した。他の給与控除を支払証明書へ推測転記しない。今後既存generator原典が変わった場合はhashとbasisを再レビューする。
- 既存のバックアップ・復元・承認条件、本番helper/権限/実2接続の競合とconsumer実PDFを確認してから本番導入へ進む。負のnetを禁止する条件は追加しない。0丸め・繰越・送金・回収は実装しない。

Supabase/Postgres skillと公式Database functions資料を参照。changelog.md取得はUnsupported content-typeで未達。新Supabase API/依存更新はなく、既存Postgres関数と固定schemaの候補だけ。FlutterSDK・公開push・PR・main・Mac・本番・実通知変更0。
