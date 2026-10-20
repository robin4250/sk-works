# 支払証明書の経費−1,000円：本番連動の残工程

基準: build 6 source d70b90b9 / 引継ぎコミット075b4004。これは本番適用指示や成功記録ではない。

## 調査結果

- 月次支払一覧は `PaymentCertificateRepository.maybeCreate(enableExpenseDirectionV2: true)` を使用済み。
- 支払一覧・計算明細・経費明細は `x-sko-payment-source-version: 2` を送る実装済み。capability応答のcompany/actor/contract/version/read_enabledを厳密確認してからv2を読み、保存envelopeと内訳・gross/deductions/netの一致を検証する。
- 方向付きv2が未有効、既存v1 draftも未変換という引継ぎ状態では、build更新後も旧保存値の+1,000円が残り得る。表示だけ−へ反転する修正では保存値・消費記録と不一致になる。
- `expense-prepared-rehearsal-txpxztbu` のOFF導入/actual-after/未使用undo成功は既存実績として再利用する。新しいnative helperや別の符号計算を再実装しない。

## 次に必要な区別

| 段階 | 既存成果 | 本番に必要な確認 |
|---|---|---|
| OFFコード導入 | support/expense-catalog-path-native-20261020 / af5ba7bb とprivate prepare記録 | exact fresh原本/関数・trigger・ACL/金融hash、専用driverのpre-COMMIT guard、COMMIT不明時のread-only recovery、未使用undo |
| 旧clientからのv2隔離 | payment_expense_source_negotiation_20261020.sql.review-only | 既存RLSを保持、restrictive policyとSECURITY DEFINER reader両方を照合、古いclientへv2を読ませない |
| owner端末のv2読取 | mainの同company/actor capabilityとヘッダ実装 | 本人端末の実応答・帳票表示。source統合だけを実端末rollout成功扱いしない |
| gateの対象限定有効化 | direction gate / rollout verified gateは別 | 正しい会社の承認済み範囲、既存row保持、他社OFF、実client確認。単にselect trueへ変更しない |
| 既存v1 draftの変換 | expense_payment_v1_draft_conversion_20261019.sql.review-only | exact before_row/hash/private backup/restore、revision/source/未確定/未消費を限定、同IDでgross0/deductions1000/net−1000、retry receipt確認 |

新規自動生成と既存draft変換は別工程。OFF導入しただけでも−1,000円は反映されない。既存記録から今回対象のexact doc/company/subject/monthが不明な場合は推測しない。

## 今回追加した安全な観測

`expense_payment_readonly_readiness_20261021.sql` はpg_catalogだけを読む在庫query。12関数の存在・本文MD5・owner/config/API実行権、constant-OFF本文、restrictive policy、trigger、変換receipt表の存在を返す。金融行・申請者・金額・ID・関数本文は返さず、アプリ関数を呼ばない。

結果はinventoryであり、安全性合格やON許可ではない。`constant_off_source=false` はONと断定せず、会社限定関数または未知本文として原本と比較する。source hashはreviewed原本と照合する。query自体は本番未実行。

検証: PGlite 0.3.14のisolated fixtureで未導入→8関数OFF導入→conversion候補追加の各状態、source negotiation未導入を正しく区別。読取前後のcatalog/bodyhashと金融件数不変を確認。既存source negotiation fixtureも成功（正確なversionヘッダ、旧client table/RPC拒否、他社/未所属拒否、金融row/既存権限不変）。Flutter起動・本番接続・DDL/DML・gate ON・実額変換・外部送信は0。
