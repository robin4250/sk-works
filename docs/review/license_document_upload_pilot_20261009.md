# 運転免許証upload pilot：実migrationの隔離検証

基準main d7dcd723＋root作成migration `20261009111338_license_document_upload_pilot_contract.sql`。本資料は本番適用/対象ON/免許証403解消の実機証拠ではない。

先行#833は比較用policyだった。本試験はrootのdeployable SQLを改変・抜粋せず実行し、移行前条件、既存保存データ、会社/本人/限定people権限、Storage INSERTを検証する。対象schema/helper/policyと列ACLはroot提供read-only metadataを限定再現し、個人情報や本番UUIDは使わない。既存helper関数の本体は合成stubで、全本番定義との一致確認はrootの適用前snapshot層が別に必要。

## 停止契約と保存済みデータ

元INSERT pauseはPUBLIC roles[0]/RESTRICTIVE、3 official bucketを停止する完全式。root549e656ではPUBLIC側は旧bucket条件又はcurrent_user authenticatedとし、authenticated専用の追加RESTRICTIVE INSERT policyで旧bucket条件又は選択worker/helperに限定する。anonから新helperをplanさせず既存の非official許可を保つ。既存account ALL、history DELETE/UPDATE、PUBLIC UPDATE pauseのroles/command/using/check完全契約を置く。workerはtable SELECTを付けずid/company_id/name/status/user_idの列SELECTだけ、関連3tableはSELECT、会社/本人/people読取とaccount RLSを置く。

18個の負条件：INSERT pauseの欠落/式/roles改変、保持guard/helper欠落、worker列SELECT/requirement tableSELECT欠落、既存4guardのusing/check/roles弱体化。各回を独立transactionで実SQLへ投入し拒否後ROLLBACK、pilot table不在と旧status/history/storage/trigger/guard/helper/列ACL不変を確認する。弱体化した条件を強制上書きせず停止する。

合成保存status＋audit history＋旧Storage object＋保持台帳を先に作り、audit triggerを有効なまま検証する。schema適用だけでこれら全row、trigger定義/OID/enabled、既存guard/helper定義/ACL、worker列ACLは不変。pilot行は0、helperはinvoker・anon EXECUTE拒否。schema適用とgate ONを分離する。

## 実Storage SQL policyの55ケース＋旧非official境界4ケース

- 空pilot/OFFは本人・既存people managerとも停止。合成operatorが選んだ会社/要件ID/要件名snapshotの1組だけを別操作で有効にする。
- 有効な本人新規own-upload/保存status、people managerの他worker添付だけ許可。一般同社の他worker、別会社、不正company/worker/requirement/status tuple、欠損UUID、過剰segment、空filename、traversal、危険拡張子を拒否。
- jpg/jpeg/png/pdf/heic/heifを許可。上位caseをclient側で拡張子lowercaseにする契約を維持し、大文字JPGはfixtureで拒否確認。
- 同じ要件IDを別書類名へ改名すると許可停止。別IDへ同じ名前を付けても停止。inactive worker/requirementや削除済み要件は、stale pilotがあっても停止する。
- 他2bucket停止、anon/null UID/削除制限のINSERT拒否、他社/anon/削除制限からpilot読取不可。client pilot INSERT/UPDATE/DELETEは拒否する。新しいMaster/会社role/featureを付与しない。
- 旧保持object UPDATE/UPSERT/DELETE、upsert:false同名再INSERTを拒否。worker列SELECTは可能だがSELECT *は拒否する。

例外許可後も旧status/history/objectを保持し、既存trigger・helper・RLS guard・元worker ACLを照合する。新しいpilot行/新objectだけがfixtureの意図した差分。本番データbackfill、専用銀行/マイナンバー経路の一括許可、設定UIはない。

追加4ケースはanon/authenticatedそれぞれ既存非official許可/拒否のbefore/afterを比較する。旧9777f99ではanon許可がhelper EXECUTE 42501へ変化し失敗したため、旧head44483bd8は統合不可。root549e656のrole分離sourceでは4ケース全て不変を確認した。

ローカルPGlite0.3.14成功。専用workflowは同じ18＋55＋4ケースをPGliteと実PostgreSQL17へ実行する。PG17はローカル固定fixture URL・空schema条件以外を拒否。実Storage service HTTP、署名URL、実iPhone、新object uploadとstatus更新の原子性、全歴史schemaは未検証。Storage SQL成功をHTTP403解消や実機確認済みとは扱わない。

実行: `node tool/verify_license_document_upload_pilot.mjs <pglite/dist/index.js>`。
実PG17: 既存 `SKO_PAID_LEAVE_FIXTURE_URL` 固定ローカルfixtureを使い `node tool/verify_license_document_upload_pilot.mjs <pg/lib/index.js> --pg17`。

参照Issue #273。本番接続/DDL/DML/対象ONなし。migration変更担当はrootだけ、検証担当は新tool/assertions/workflow/docsだけ。
