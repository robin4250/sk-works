# build24 会社間連携候補

## 既存の再利用
mainの `supabase/migrations/20261015005238_company_link_requests.sql` を取得して確認。`request_trade_company_link` / `respond_trade_company_link` は両社の承認と開始月を管理し、`attach_approved_trade_link` は linked_company_id、法人番号の順に既存trade_companiesを再利用する。同名だけなら拒否し、既存連絡先を保存する。既存confirmの直接連携は拒否される。

## YES/NO
既存協力会社レコードの選択が必須。NOは所属切替だけ。YESは既存相互承認フローに接続し、新会社側の取引会社に元会社をcustomerとして反映する。片側管理者の選択だけで他社承認を代用しない。すみだ建設という文字列を固定せず正規company IDを参照する。既存取引会社のroleがsubcontractorなら承認時にbothへ拡張する既存挙動を維持。

会社IDとの既存リンクがない協力会社は、別担当の本人・代表者・会社照合でcanonical company IDを検証してから処理する。会社や本人SKO IDをここで発行しない。

## 候補の範囲
`tool/company_link_plan.mjs` は計画のみ。認証済みと仮定して公開APIに直結してはいけない。入力はサーバーが権限確認して取得する必要があり、保存直前のセッション、代表権、マスターの全体フラグ、切替日、会社休止状態、リプレイを同じトランザクションで再確認する。既存会社間APIのfirst-company helperを新しい明示会社選択の代理にしない。

ON/OFFは親担当の全体マスター機能5種契約に従う。処理途中OFF時はDBロック・再確認で新規連携を拒否し、既存データは消さない。所属切替と会社連携の一括処理は冪等command IDと成功receiptが必要。YESの会社承認未成立なら『連携待ち』とし成功と表示しない。

本候補は金額・機密書類・給与記録・資格・認証を移行/公開せず、DB変更も行わない。

## 検証/未完成
Node合成7件成功。実DB/PostgREST/RLS/同時実行/画面/マスタースイッチ/所属切替/実会社間の接続は未完成。本番導入不可。既存の会社間連携が現在の本番へ配備済みかはここでは照合していない。最新main取得はコードの存在確認のみで、実施済みの証拠ではない。
