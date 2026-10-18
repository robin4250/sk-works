# 支払経費v2：保存済みrow読取境界の接続候補

方向契約`8bdc579e`を再利用する次工程。新規read-only adapterと専用fixtureのみ。既製品consumer/PDF/SQL/RLS/Auth/給与/経費精算選択は無変更。

## 現コードの接続箇所

- `payment_certificate_repository.dart`のloadCertificatesはcompany_id条件でrowを読み、gross/deductions/netをnum.toInt/default0、periodをDateTime/default現在日で構築し、snapshotをv1 parserへ渡す。将来v2採用時はcompany_idもselectして欠落・型不正・対象違いをfailclosedにし、既v1は維持する。
- `PaymentCertificateRecord.expenseCost`はv1型だけ。v2をこの値へ偽装すると符号が消えるため、方向を保持する別memberか明示unionが必要。
- `payment_certificate_pdf_service.dart`の_sheetはgrossから経費を引いて基礎行を作り、経費を加算する。v2時だけgrossを元工事額として保持し、差引行−原額と保存deductions/netを同時に使う必要がある。rendererだけ先行変更しない。
- invoice readerは加算のまま。payroll/cash/paidの選択は申請者返金手段であり、このadapterはそれを読まず、禁止や金額加算へ変換しない。

## 今回の候補

`ExpensePaymentReadCandidate.read`は現在の支払row形状を入力し、company/doc/partner/period/revisionと金額型を厳密確認してimmutableな読取projectionを返す。v2用のnested snapshot key `expense_cost_direction_v2`は今回の接続案であり、まだbackend応答には存在しない。旧expense_extra_*と混在すると拒否。v2異常時にv1へfallbackしない。

v2は既定OFF。明示的な導入確認、同じcontext/revisionへ結び付いた独立の非経費gross/その他控除basis、同じ会社/doc/相手/月/版を持つdetail envelopeをすべて要求する。導入確認boolは権限証明ではない。basisは旧v1 grossから経費を逆算して作らず、既generatorの経費計上前の算定結果から一括取得する必要がある。signed net−1,000も元契約どおり受理する。

v1の確定済み経費のみ+1,000はそのまま+1,000として読み、snapshot/保存gross/deductions/netを書き換えない。v1へv2 evidenceを渡して符号だけ反転することも拒否する。

## 次のbackend/実consumer工程

1. 保存済み基礎generatorの固定原典と実schemaを照合し、経費適用前gross/既控除を同一トランザクション内で取得。新draftだけv2のsnapshot・gross/deductions/net・detailを一貫保存する候補を準備する。
2. 旧v1・手編集・確定帳票・expense_amount_consumptions/purpose cost_recoveryのfreezeと履歴を保持する。方向変更で同じclaimを再消費しない。振分け/再生成/確定/取消のnative複数接続競合を検査する。
3. 新v2能力と正規読取APIのscopeを検証した後、Recordのunionと専用PDF branchをまとめて接続する。古いclientへ未知versionを配信しない。
4. invoice加算と費用負担方向、申請者の精算3択を独立に検証する。給与consumerはMac境界維持。実backend/本番反映/実PDF/実機の成功とはまだ扱わない。

今回のfixturesは固定合成rowを使うconsumer境界の検証。実DB/JWT/RLSやnative transactionを証明しない。本番適用は既存のバックアップ・復元・承認条件を維持する。
