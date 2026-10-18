# 経費の帳票方向：version 2契約候補（未接続）

基準main `bedac66af938989a9e9d314ee2d96cd01b831a01`。ユーザー再確認：経費申請由来の1,000円を下請け支払証明書で差し引く。取引会社請求書では原額を加算する。費用負担側の帳票方向と申請者の給与精算／現金精算／支払い済みは別軸。本候補は給与型や精算方法を持たない。

## 現状と変更しない部分

既存`ExpenseCostSnapshot`はversion 1の加算保存契約で、既存SQLは支払grossへ経費を加算する。既存PDFは保存総額と内訳を整合させるため加算表示する。PDFだけマイナスに変更しない。既v1、確定帳票、原額内訳、既消費履歴、invoice consumer、支払consumer、renderer、SQL、給与は一切変更していない。

新候補は`ExpenseCostDirectionV2Candidate`で、既consumerから未参照。backendが採用済み／本番保存可能という意味ではない。明示v2の内部検査投影に限って既v1のID・revision・原額・合計・immutable／verifyDetailsを再利用する。保存済みv1をv2へ自動変換する経路はない。

## 明示wire契約

11項目の完全一致を要求する：`version=2`、`contract=expense_cost_direction`、`document_kind`、`direction`、`company_id`、`document_id`、`subject_id`、`month`、`document_revision`、`amount_yen`、`claims`。

kindはinvoice/paymentCertificateだけ。invoiceはaddition、paymentCertificateはdeductionだけ。signed deltaはraw入力を受け取らず原額と方向から導出する。余分な`settlement_method`、`payroll`、`signed_delta_yen`も拒否する。

会社・帳票・相手先UUID、月YYYY-MM、帳票revisionを呼出側の固定対象と完全照合。各claimはid/revision/amount_yenの3項目だけを受理し、UUID重複（大文字小文字違いを含む）、revision非整数・1未満、原額0以下、合計不一致を拒否する。総原額は非負整数で0円は空claimsだけ。整数はJavaScriptでも正確な2^53-1以下に制限し、集計前に上限超過を拒否する。これは業務上限ではなくwire数値の精度境界。

## 候補の金額整合検査

支払：基礎grossを保持し、既存その他deductions＋経費原額＝保存deductions、gross−その他deductions−経費原額＝保存net。20,000円・その他控除500円・経費1,000円ならgross20,000／deductions1,500／net18,500、表示差分−1,000。

請求：既に福利厚生費・税を含んだ基礎合計23,760円に原額1,000円を一度だけ加算し24,760円。福利・税へ経費を再加算しない。表示差分＋1,000。

これらは候補の保存整合を検査するpure関数で、現在の帳票を再計算しない。追加のユーザー実例は工事行なし・経費1,000円だけであり、gross0／その他控除0／経費控除1,000／net−1,000の符号付き保存整合を受理する。経費が支払可能額を超える場合も正しい負のnetを拒否しない。gross・原額・控除は非負、netのみ±(2^53−1)の整数を許可し、その他控除＋経費の合算前に精度上限を検査する。0丸め・繰越・自動送金・債権回収を実装しない。この候補だけを根拠に既存generatorを停止／変更してはいけない。

## 後続backend接続の条件

- 最新本番helper／権限／固定原典／バックアップ・復元・承認条件を満たしてから別工程で設計する。
- 新方向は明示的な新versionだけへ導入する。確定・手編集・旧snapshotを勝手に再生成／反転しない。v1を読める旧clientへv2を誤配信しない。
- 既`expense_amount_consumptions`とcost_recovery purposeのfreeze・原額・claim revision・対象帳票／版の履歴を保持する。同じ経費をv1加算とv2差引へ二重消費しない。帳票間付替え・再振分け・確定／解除との実row lockとCASを検査する。
- 新draftのgross/deductions/net、原額snapshot、detail reader、PDF1枚目／内訳ページが同じ方向・対象・版へ接続されることを一括検証する。PDF符号だけ先行変更しない。
- 経費のみでnetが負になる帳票もユーザー指定どおり差引として保持する。非負netを本番適用の追加条件にしない。自動送金・繰越等の新業務を推測追加せず、申請者への返金・給与consumerと相手先帳票の差引を混同しない。

本番データ/RLS/Auth/権限・SQL・既snapshot・帳票renderer・給与・Mac・公開pushは変更ゼロ。

## 追補：ユーザーの経費のみ実例へ訂正

旧commit `aa883ebd` は超過を一律「未確定」とする候補だったが、ユーザー提示のgross0／経費1,000円を−1,000円とする指示に対して過剰な拒否だった。履歴は保持し、新commitでsigned net整合を受理するよう訂正。既確定v1を読み替える変更ではない。本番適用は既存のバックアップ・復元・承認条件だけを維持する。
