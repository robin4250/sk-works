# 支払経費v2：実Record・repository・共通PDFのopt-in対応

基準はreview-only backend候補`b388a029`。既v2契約とrow adapterを再利用し、製品の実consumerへ安全な分岐を追加した。本番・新Releaseへ適用したという意味ではない。

## 実sourceの接続

- PaymentCertificateRepositoryは`enableExpenseDirectionV2=false`が既定。既存callerはそのままOFFで、能力RPCや新明細RPCを追加発行しない。opt-inの場合のみ`expense_payment_direction_capability`の7keys、会社/現在actor/marker/version/支払種別/対応source版/read_enabledを厳密確認する。
- v2保存rowが来て能力を確認できない場合はlegacy扱いにせず読み取りを止める。会社・帳票・相手・完全期間・revision、独立基礎額、同版detail、gross/deductions/signed netを既adapterで照合する。ログイン切替は途中で元に戻るABAも結果を返さない。
- Recordは既v1expenseCostを残し、v2の検証済みreadを別memberへ保持する。PDF生成前にRecordとreadのid/相手/完全期間/revision/保存金額を再確認し、v1/v2混在を拒否する。
- 実PaymentCertificatePdfService.buildPdfでv2経費行−原額、小計にも同じ差引、保存netを使用する。工事なしなら架空工事行を作らない。原額明細ページも「加算」ではなく「差引」と説明し、申請原額は正数のまま表示する。
- 既プレビュー・printCertificate・共有は同じbuildPdfを使う。別rendererや独自テンプレートは作らない。invoiceは原額加算、旧v1支払も加算表示を保持する。

## backend候補のread-only能力

review-only SQLへ公開invoker wrapperとprivate権限判定を追加。本人認証/account利用可・同社owner/admin/managerだけが読める。private generator gateは常にfalseのままであり、source version 2対応を実装しただけでは有効化しない。fixture内だけ指定会社をONにする。実本番DDL/権限付与はしていない。

## 実行検証

専用fixtureは実Supabase SDK repository→Record→実buildPdfを使い、経費のみv2、工事ありv2、旧v1の3PDFを生成する。−1,000／19,000／旧+1,000、default OFF、新能力の不正/他社/他actor、row/明細revision/金額改ざん、actor ABA、PDFの不整合Record拒否を検査する。既expense_cost_document_testも変更せず成功し、invoice/PDF原額検査を保持した。

`tool/verify_payment_expense_direction_consumer_pdfs.py`で実出力文字を検査し、v2の行・小計・総額・差引説明とv1加算の保持を確認した。3表紙とv2明細をPNGへ描画し視認確認。単なるsnapshot/parser合成ではなく実consumer出力の証拠だが、実backend/JWT/RLS/実機の保証ではない。

SQL verifierも新能力OFF/ON・本人会社スコープ・非所属拒否を加えて成功。元のgenerator→保存→確定→freeze/1消費の検査を保持する。

## 有効化前の残条件

本番helper/schema同等性・native二接続競合、既バックアップ/復元/承認条件、旧clientへのv2誤配信防止を満たすまでgateをONにしない。旧v1/既確定/手編集を自動反転しない。実ユーザーの既v1draftを差引へ変更する処理は別の明示工程であり、今回のsourceで書換えない。精算3択や給与consumerには変更ゼロ。
