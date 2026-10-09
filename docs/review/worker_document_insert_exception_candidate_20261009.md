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

39チェックでbaseline拒否、権限A/B/Cの差、別会社/別worker/status/requirement不整合、不正UUID/過剰segment/空filename/危険拡張子、anon/nulluid/削除制限、他2bucket拒否、保存旧物へのUPDATE/UPSERT/DELETE拒否、upsert:false重複拒否を確認。3既存guard（account_deletion_access_guard ALL、official_document_history_no_overwrite UPDATE、official_document_history_no_delete DELETE）のpolicy本文は比較前後で不変。retained object payloadも保持する。

ローカルPGlite0.3.14成功。実Storage HTTPアップロード、本番403解消、status更新との原子性、実iPhone操作、歴史audit triggerの完全schema共存は未確認。新しいINSERTオブジェクトに対応するstatusの更新失敗や後続cleanup失敗を、保存成功として報告しない。別担当repository/UI修正とrootの本番判断が必要。

実行: `node tool/verify_worker_document_insert_exception_candidate.mjs <pglite-dist/index.js>`。
本番接続・DDL/DML・Auth/RLS変更なし。参照Issue #273。
