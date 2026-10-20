# 注文書の相手先登録情報：取得元の限定補完候補

基準main `ab9e13fa`。**review-only・本番未適用・製品未接続の追加候補。** 変更対象は既`private.trade_document_source(text,uuid,text)`だけ。正式migration・本番適用は統合担当が別工程で判断する。`trade_document_template`は変更しない。

## 原本と対応の確認

- `20261014124714_monthly_trade_document_attachment.sql`の支払証明書sourceは、相手先を同じcompany_idとpayment certificateのpartner_company_idで`partner_companies`から読む。住所・president_nameは読むがcorporate_numberは常に空文字。
- `20261004132001_add_trade_company_master_and_contract_sources.sql`の`trade_companies`にはcompany_id、partner_company_id、trade_role、住所、法人番号がある。`20261011205233_trade_company_representative_contacts.sql`は代表者名を同じdirectory行に追加し、`save_trade_company_contact`は既company-scoped saveを委譲した後、このdirectory行の代表者名を更新する。
- legacy link作成と`sync_trade_company_directory`には名前類推・`limit 1`が残る。しかし今回の帳票sourceはそのhelperを呼ばず、現在保存されている明示partner FKだけを使う。
- `(company_id,partner_company_id)`の一意制約は確認できない。名前indexはuniqueでない。重複がある前提で扱い、名前や作成順で1行を選ばない。
- directory workspaceはowner/admin限定、支払証明書sourceはmanagerにも読取可能。この差を広げないため、既`can_manage=true`（owner/admin）だけに追加補完を許す。managerの既source値を変えない。

## 候補の内容

`payment_order_directory_party_source_20261021.sql.review-only`は既base source本文と既税額fallbackだけ適用した本文のexact MD5を許可する。未知source・再適用を拒否。owner=postgres、SECURITY DEFINER、空search_path、volatile、owner以外のEXECUTEなしを要求し、`pg_get_functiondef`の宣言と戻り直前だけを局所置換する。CREATE OR REPLACEによりOID/owner/ACL/その他metadataを保持する。新API・GRANT・RLS・Auth・table/index・会社行や金融行のUPDATEは追加しない。

新規支払証明書別添のdefaultsに限り、次のすべてが成立する時に住所・法人番号・代表者名を補完する。

1. 既sourceの認可・元帳票revision・対象月検査を通過。
2. actorが既can_manage=true。
3. 同company_id、同partner_company_idに対応するdirectory行が厳密に1件。
4. そのtrade_roleがsubcontractorまたはboth。
5. 同subject/companyの保存済み別添がない。

directoryの各値は既`save_trade_document_attachment`の型・長さ・形式に収まる場合だけ独立に採用する。text列からtrim後の住所1〜240文字、代表者名1〜80文字、法人番号ASCII数字13桁を受理し、空欄・長すぎる値・不正形式はそのfieldだけ既partner値・空欄へ戻す。他のvalid fieldの補完は継続する。相手先名・issuer・金額・税額・source_fingerprintは変更しない。件数と各値は同じSELECTの集約で読むため、count確認と別SELECTによる任意行取得を分離しない。

**対応なし・他社のみ・別partner・複数対応・不適切roleでは補完だけを拒否し、元のpartner値・空欄を維持する。帳票全体を新しいdirectoryエラーで停止しない。** 曖昧対応の解消案内など新workspace状態は今回追加していない。

保存済み別添があれば補完自体を省略し、後日のdirectory変更・重複でも既workspace/保存payloadを維持する。明示的に新規別添を保存した後はそのparty snapshotが保持される。既保存別添への一括更新や、source revisionを変更せず差し替える処理はない。

## PR1307自己プロフィール候補との分離

`origin/support/partner-company-profile-candidate-20261020`の`partner_company_profile_20261020`候補を読取比較した。自社代表者はprivate extensionの会社本人申告であり、local trade_companiesの他社連絡先とは別原本である。今回directory代表者名をissuerへ流用しない。linked_company_idで相手会社のcompanies/private profileをraw参照せず、相互開示helperの配備を仮定しない。PR1307のschema・RPC・認可・相互表示・自己プロフィール設定を再実装していない。

## 隔離検証

`tool/verify_payment_order_directory_party_source.mjs`は既月次別添fixtureを再利用し、PGlite 0.3.14のbase source／既tax fallback sourceの2構成で成功。

- 同company・明示partner・適正roleの一意directoryから新規defaultsへ補完。
- foreign-companyと別partnerの値を混ぜない。viewer/他社actorは既42501拒否。
- managerは従来partner住所/代表者・法人番号空欄を維持。
- blank、both、customer-only、複数directoryの補完可否を検査。曖昧時も帳票取得は継続。
- 住所240/241文字・代表80/81文字・法人13桁境界、12/14桁・全角数字・英字混入、trim後境界を検査。不正fieldだけ従来値へ戻しvalid他fieldを独立採用した各9caseを、両sourceで既save normalizerを通して保存成功後rollback。
- 既保存workspace、invoice、元payment certificate行、別添保存行を候補適用だけで変更しない。
- 正規保存で補完済みpartyをfreezeし、directory変更後も保存済み値を保持。
- source fingerprint不変、OID/owner/ACL/security/search_path等metadata保持、予期しないauthenticated EXECUTE grantを適用前に拒否、未知本文/再適用を拒否。
- 既fixture内の認可・CAS・税・確定保護・旧別添保持の検査も継続成功。

初回wrapperはdata URL実行時のabsolute module path解決とactor文字列の埋込みに誤りがあり、製品SQLを緩めずfile URLとparameterized set_configへ補正した。前段失敗はfixtureの実行準備/合成入力であり、本番障害ではない。

## 未達条件

PGliteの簡略schema上の結果であり、本番のdirectory対応分布・現source/全metadata・本番RLS/同時権限失効・native PostgreSQL同時編集・実機PDFまで証明しない。mainにある元migrationと本番関数の同一性は未照会。本番適用前に原本/ACL/metadataをfresh照合し、他のsource変更と直列に統合・backup/復元準備する。今回候補で許可したbase/tax以外のsourceは再レビューが必要。

旧同期の名前推定で既保存FK自体が誤対応になった履歴までは、同一会社・一意の現FKだけで否定できない。登録対応の確認は正規管理画面で行い、候補が名前から関係を新規推定することはない。既存local directoryの住所・代表者・法人番号を管理者登録内容として読むもので、法人情報の外部真正性検証ではない。

本番照会/DDL/DML・金融修復・Auth/RLS変更・実通知/招待・外部送信・Release作成/導入は0。Flutter/PDF生成は行っていない。

## 独立レビュー後の保存契約補修

初候補はdirectoryの非空文字をそのまま採用していたが、directory住所/法人番号は無制約、代表者200文字に対して、注文書保存は住所240・代表80・法人ASCII13桁であり、補完値によって自動表示と保存の契約が食い違うという指摘を受けた。関数認可・metadata・fingerprint・保存済み保持を変えず、戻り値の各field選択だけを保存契約に合わせた。無効なdirectory値で文書全体を停止せず、既値を保持する。

**旧partner値そのものが長さ・形式など既保存契約の範囲外だった場合、その修復は今回の補完候補に含めない。** 元値を勝手に切り詰めたり消したりせず、正規の会社情報編集で確認・修正する必要がある。
