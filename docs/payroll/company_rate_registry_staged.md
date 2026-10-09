# 会社給与料率registry（未適用）

Issue #273の会社給与料率の永続化基礎。CLI 2.120.0のmigration newで生成した`20261009151946_company_payroll_rate_registry.sql`。
本番・リンク済みDBへ未適用。初期値seed、給与計算切替、既存画面変更、既存company_rate_settingsの請求税率・福利厚生率への書込はない。

## 保存・権限

専用非公開schema `payroll_rate_private`の現在設定・検証候補・旧新履歴、会社対象条件とその別履歴。全tableにRLSを有効化し、anon/authenticated/PUBLICのraw table権限を撤去する。
publicの3RPCはSECURITY INVOKER、呼出先のprivate SECURITY DEFINERはempty search_pathと会社IDに一致する既存company_members owner/adminおよびprivate.account_access_allowed()を毎回確認する。
既存membershipやAuth helperを変更しない。新APIでもworker・他社adminに給与料率を公開しない。

標準5種類のitem_idはkind固定、customはUUID文字列。標準同kind重複と会社内のtrim・小文字化後のlabel重複を拒否する。初回expected_version=0、保存後1から増加する。
料率と会社対象条件で共用する会社別advisory lockと現在行lockで初回作成も直列化し、expected_version不一致を拒否する。
率は百万分の一percentage整数（0..100000000）。totalとemployee/employerの和を照合し、単純な÷2をしない。
既存itemのkind変更を拒否。所得税kindは拒否し、税額表は別stageとする。

## API shape

- `read_company_payroll_rates(p_company_id)` → `{items:[{item_id,version,value,origin}],candidates:[{candidate_id,item_id,value,checked_at,scope_version}],company_scope:nullまたは{version,value,updated_by,updated_at},scope_history:[{version,before_value,after_value,actor_id,changed_at}],history:[{item_id,version,before_value,after_value,before_origin,after_origin,candidate_id,actor_id,changed_at}]}`
- `save_manual_company_payroll_rate(p_company_id,p_item_id,p_expected_version,p_value,p_confirmed)` → `{item_id,version,value,origin:"manual"}`
- `save_company_payroll_rate_scope(p_company_id,p_expected_version,p_value,p_confirmed)` → `{version,value,updated_by,updated_at}`。
- `apply_company_payroll_rate_candidate(p_company_id,p_item_id,p_candidate_id,p_expected_version,p_confirmed)` → 同shape、originは`official_candidate`。

valueは`{kind,label,total,employee,employer,insurance_month,payroll_month,payment_month,source:{url,publisher,document_hash,applicability}}`。
kindはhealth_insurance/nursing_insurance/pension_insurance/employment_insurance/child_support/custom。
payloadは32KiB以下、label80文字以下。source URL2048・発行元200・資料識別256文字以下。applicabilityは最大20項目、key80・value512文字以下の空でないstringに限定する。
3monthはYYYY-MM-01。sourceはHTTPS URL、発行元、資料識別文字列、空でない対象条件object。
manualのdocument_hashに管理者入力識別文字列を使うことは可能だが、正式資料hashとして検証済みとは扱わない。
候補取得・表示だけで現在設定は変更されない。適用項目の保存と旧新履歴は同一transaction。
確認popupは画面で表示し、率・各適用月・情報元を本人確認した後だけp_confirmed=trueを送る。DBフラグだけで本人確認を代替できない。

## 検証候補の境界

一般管理者向けの候補登録・verified更新RPCは存在しない。raw candidate tableのINSERT/UPDATE権限もない。
候補は会社ID・itemID・対象条件scope_versionに固定し、検証者・検証日時・根拠を持つ。適用APIはこのtrusted登録済み候補だけを読んで適用し、クライアント送信値を公式値として採用しない。
正式資料の取得・PDF解析・保険者/県/事業区分照合を行うtrusted登録flowはまだ実装していない。候補テーブルの所有者による直接登録は正式検証の代替ではない。
共通所得税資料の公開も未実装。既存サービスロールの広い権限やDB ownerを新たに制限する変更はしていない。
履歴はAPI経由で追加のみ。DB ownerのUPDATE/DELETEまで不変にする機構はない。
会社対象条件を変更してversionが進んだ後は旧scope_versionの候補適用を拒否する。取得済み候補を勝手に新条件へ流用しない。
現在設定の削除・廃止、期間別の複数current設定、一覧pagingは未実装。

## 実行確認と制限

正確なmigrationをPGlite 0.3.14に適用し、非owner authenticatedとanonとして実RPCを実行するfixture。
owner/admin保存、worker・anon・他社・アカウント停止拒否、raw table拒否、manualと候補の明示適用、固定整数と不等負担率、重複、version、選択項目、旧新値/actor/time、audit INSERT失敗時の設定と履歴rollbackを確認した。
fixture prerequisiteのauth.uid/account_access_allowed/company_membersは合成。完全な既存schemaや本番のAuth/MFA条件の結合検証ではない。
CIは同harnessをignore-scriptsでpinされたruntimeで再実行する。
実際の並列セッション、PostgREST schema設定、既存migration全適用、performance/security advisorsは追加確認対象。
CLI statusはDocker/Podman未導入、db advisors --localとmigration list --localはlocalhost:54322接続拒否で実行できなかった。本番へ切り替えて検証していない。
公式changelogとfunctions docsのempty search_path・SECINV・PUBLIC EXECUTE撤去を確認し、security checklistをレビューした。

## 会社の公式対象条件

会社の住所しか構造化されていない現状に対し、新company_scopeを会社別singletonの給与対象条件の大元とする。既存companiesに列を加えず、名称・住所をコピーしない。
valueは`{insurer,prefecture,employment_business}`。insurerはkyokai/union/other/unconfigured、prefectureは日本語47都道府県またはnull、employment_businessはgeneral/agriculture_forestry_fisheries_sake/constructionまたはnull。
scope未登録はreadでnull。住所から県や保険者を推測せず、管理者本人が確認して保存する。scope未設定でもmanualrate保存は可能で、その手入力を公式検証済みとは扱わない。
source.applicabilityはその料率を登録した時点の証跡snapshotで、会社scopeのcurrent条件とは区別する。
scope保存も権限、確認、expected_versionを必須とし、旧新値・actor/timeをscope_historyへ同一transactionで保存する。料率historyへscope変更を混ぜない。
fixtureではscope保存/未設定null、会社跨ぎ/worker/anon/account拒否、値検証、version競合、scope変更後の候補拒否、別履歴、scope audit失敗時rollbackも確認した。

## 会社削除のライフサイクルと履歴保持

既存`20260922013000_add_admin_initial_setup_wizard.sql`のcompany_rate_settings.company_idはpublic.companiesにON DELETE CASCADEで結び付く。
新しいsettings/candidates/company_scopeの現在状態もこの会社設定ライフサイクルに合わせてON DELETE CASCADEとする。既存companiesやそのDELETE policy自体は変更しない。
新history/scope_historyのcompany UUIDはlogical attributionとして保持し、company FKを付けない。変更の旧新値・操作者・日時を保存する今回の要件に合わせ、会社削除時にこの証跡を自動消去しない。名称・住所のコピーや新しいTTLは作らない。

既存資料`docs/recovery/account_deletion_source_20261008/account-deletion/policy.mjs`はpayroll等をretainedCompanyRecordsに含めるが、officialDocumentRetentionFinalized=falseである。
これはアカウント削除の資料で、会社削除やすべての履歴の確定保持期間を定めるものではない。既存worker_document_status_historyには会社FK cascadeの別契約もあるため、新給与料率履歴の保持を既存全履歴の普遍的契約と称しない。
このsource設計は現在設定の削除互換と今回の変更履歴保持を両立するもので、公式帳票の保持期間やアカウント削除workerの公開承認を変更しない。

新helperはcompany_members・account_access_allowedに加え、public.companiesの現存行を明示確認する。会社rowをFOR KEY SHAREで取得してから会社advisory lockへ進み、会社削除と料率書込のlock順序を整える。
会社削除後に古いmembershipが残っていても、一般管理者に保持履歴を返さない。raw history ACLも引き続き撤去する。

fixtureでは会社DELETEの成功、current設定/候補/scopeのcascade消去、rate/scope historyの全値保持、stale membershipを持つ元owner/adminの全RPC拒否、raw履歴拒否、他会社の値と履歴不変を実SQLで確認した。
以前のNO ACTIONによる会社DELETE阻止は、この隔離fixtureでは解消している。
実本番schema全体のDELETE・JWT/アカウント削除結合、並列Postgresセッション、バックアップ、正式保持方針の最終確認は未完了。本番migrationは依然未適用。
