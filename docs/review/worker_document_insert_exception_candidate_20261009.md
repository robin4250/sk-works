# 必要書類Storage INSERT：停止例外の比較設計

基準ソースmain a086828。rootが2026-10-09に読取した本番policy metadataを受け、synthetic PGliteで候補を比較する資料。製品migrationではなく、現在の停止解除を決定しない。

本番RESTRICTIVE `initial_beta_official_documents_insert_pause` はworker-documents/qualification-certificates/employee-onboarding-documentsを拒否する。worker-documentsのPERMISSIVEは既存can_manage_people、または保存draft.upload_path/requested_byと本人workerが完全一致する経路。一般本人のpublic status INSERT/UPDATE許可だけではStorage直接INSERTを許可できない。

| 比較 | restrictive例外 | 結果 |
| --- | --- | --- |
| A | 保存statusの会社/worker/requirement/id完全一致 | managerの既存status upload可。本人directは既存permissive不一致、statusの無いown-uploadは不可 |
| B | A＋own-uploadの会社/worker/active requirement/membership/本人又は既存people権限整合 | manager新規direct可。本人directは依然permissive不一致 |
| C | B＋本人のINSERT-only permissive（同じpath/会社整合） | 本人新規/既存direct可。UPDATE/DELETE/役割付与は増やさない |

5 path segment・UUID・拡張子jpg/jpeg/png/pdf、account guard、現役workerをfixture候補条件にする。worker active条件は追加候補条件であり、本番状態/業務方針との照合が必要。保存statusと先行uploadのown-uploadを同じ前提として扱わない。draft経路は独立にexact upload_path/requested_by/worker本人を要求し、draft IDが保存statusに無い経路はAでは拒否される。draft全体を完成扱いしない。

候補のtuple評価helperは全てSECURITY INVOKERでfixture限定。新SECURITY DEFINER/APIや本番table SELECT権限を提案しない。fixtureのbusiness table読取RLSは合成した本人/同社people managerに限定する。既存has_company_feature/account_access_allowed/document_submission_access/official_document_path_is_retainedの署名・意味は合成stubであり本番実定義をコピーした証拠ではない。

59チェックでbaseline拒否、権限A/B/Cの差、別会社/別worker/status/requirement不整合、不正UUID/過剰segment/空filename/危険拡張子、anon/nulluid/削除制限、他2bucket拒否、保存旧物へのUPDATE/UPSERT/DELETE拒否、upsert:false重複拒否を確認。3既存guard（account_deletion_access_guard ALL、official_document_history_no_overwrite UPDATE、official_document_history_no_delete DELETE）のpolicy本文は比較前後で不変。retained object payloadも保持する。

repo defaultRequirementsでは運転免許証・マイナンバーカード・銀行口座情報がすべてscope=internalで、任意名称も追加できる。scopeや曖昧な名称判定だけではordinary限定を証明できない。Cを全active requirementへ適用すると専用提出/銀行口座経路との境界を越える可能性があり、既存業務分類・明示的対象範囲との照合が終わるまで本番適用不可として比較候補に留める。

fixtureのworker/status/requirements/member SELECT ACL/RLSは合成した読み取り契約。repoに本人status INSERT/UPDATEと本人又はpeople manager status SELECTの契約は存在するが、本番の全table ACL/RLS・追加guard・enum/domainと一致した証拠ではない。SECURITY INVOKER候補はこれらSELECTに依存するため、実定義metadataをrootが別照合し、アクセス失敗を解消するために一般読取権限を追加しない。

ローカルPGlite0.3.14成功。専用CIで同じ59チェックをPGliteと空の実PostgreSQL17へ実行する。PG17は既存固定ローカルfixture URL guardとempty-schema guardで本番接続を拒否する。実Storage HTTPアップロード、本番403解消、status更新との原子性、実iPhone操作、歴史audit triggerの完全schema共存は未確認。新しいINSERTオブジェクトに対応するstatusの更新失敗や後続cleanup失敗を、保存成功として報告しない。別担当repository/UI修正とrootの本番判断が必要。

実行: `node tool/verify_worker_document_insert_exception_candidate.mjs <pglite-dist/index.js>`。
本番接続・DDL/DML・Auth/RLS変更なし。参照Issue #273。


## 免許証だけを明示再開する最小候補D（まだ未適用）

Cを全activeへ適用せず、内部の `(company_id, requirement_id, enabled)` allowlistをAND条件として追加する。初期空/default false、rootが対象会社の運転免許証要件を個別確認した組だけを有効候補とする。特定会社名や実UUIDは公開資料/CIへ掲載しない。任意name、scope=internal、名前の変更/一致から許可行を作らず、別IDの同名要件は拒否する。選択IDの表示名変更は同じ枠の扱いであり別IDに展開しない。要件を別種類へ転用する場合は許可を停止し、再確認する運用が必要。

会社/worker/要件の所属、is_active、現役worker、account guard、既存本人又はcan_manage_people、pathと拡張子条件はCのまま必須。本人INSERT-only permissiveと既存manager/draft permissiveはDのrestrictive条件にも必ずANDされる。他の必要書類、マイナンバー、銀行口座、他2bucketは自動再開しない。保存historyのUPDATE/DELETE holdは変更しない。設定UI、setter RPC、Master/会社role/feature付与は追加しない。

真にprivateでSELECT不可なallowlistはSECURITY INVOKERから読めない。新SECURITY DEFINERを増やさない比較fixtureでは、allowlistの3列にだけauthenticated SELECT、既存会社membership+account guardで自社行だけ見えるRLS、INSERT/UPDATE/DELETE拒否を付けた。private schemaをDataAPIへ新公開しない。これは本番で既にある権限ではなく、候補Dに必要な限定metadata読取の追加として明示的なreview対象。追加grantも避ける場合は、保護された適用SQL内のexact組条件等を別設計する必要がある。既存個人情報/登録情報のtable権限を広げて解決しない。

root提供のfresh metadataに合わせworkersはtable-level SELECTを与えず、id/company_id/name/status/user_idの5列SELECTと会社membership読取に寄せた。SELECT *・余分な個人情報列は拒否し、invoker tuple helperは5列だけで成功する。company_members/requirements/statusesはSELECTあり、business table account guardも合成追加。owner管理ALL等を含む全live policyコピーではなく、今回必要なSELECT経路の限定再現である。

追加20チェック：worker5列読取/全列・余分列拒否、allowlist空/OFFの本人・manager拒否、明示license組のみ本人/manager許可、他internal/同名別ID拒否、名称変更で別要件へ広がらない、client gate INSERT/UPDATE/DELETE・余分列読取拒否、他社/anon/削除制限のgate読取拒否、削除制限ユーザーの有効license INSERT拒否。合計59チェックがローカルPGliteで成功。新production migration・本番対象識別/ON操作は未作成・未実施。
