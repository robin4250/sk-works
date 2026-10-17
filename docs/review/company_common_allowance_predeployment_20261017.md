# 社内共通手当：追加登録を本番利用する前の適用レビュー

基準source main `de0470d616b480d98ee84ec47fb67ee4b5ea036e`。対象client候補はDraft #1234 `3aa57d2fb0b9be74187ba4ea9023d70fb5d4d784`／tree `9410240e7413e012b9a3c47b08845b695ca902c2`。既存成果・保存証拠と下記の読取専用catalog観測を照合した文書である。文書作成時の追加本番照会、SQL適用、backup取得、実archive復元、Mac/R31実行、承認要求は行っていない。

## 現在地と適用範囲の候補

#1152（head `36aae2be9ba6783cdf5d7a8446a55f5edc9d7e34`、source merge `657192dea7535288fd16db833219e1bd241cc7da`）と#1155（head `64b249658881c8950cec5d5f5c700ada2530a107`、source merge `93695e502251630ff574bd5a25ad038f1e823173`）はGit上で統合済み。ただしSQLは `tool/*.sql.review-only` にあり、本番配備ではない。既存handoffは未適用と記録している。本監査担当は実環境を再照会せず、下記root提供の限定観測を追加した。

rootの新しい読取専用catalog証拠（[Issue #273 comment 6232207390](https://github.com/robin4250/sk-works/issues/273#issuecomment-6232207390)）：2026-10-17 **09:19Z頃／18:19JST**、SELECT直後の時計確認は `09:19:04Z`。project `ztktgquxvcxcjxtluspu` のpg_catalogでpublic関数名の存在countのみを取得し、`read_company_common_allowances_admin`／`save_company_common_allowances`／`read_company_common_allowance_request` の `public_function_overloads` は各 **0**。必要3RPCのpublic定義がこの観測時点で未導入のため、本番追加登録は利用できない。RPC自体の呼出・保存操作・旧full-saveへの迂回・業務行読取・schema/role/data変更は0。署名やREST schema cacheの動作は未検証で、残る依存全体の状態はこの3name集計から推測しない。

追加の読取専用catalog観測では、SELECT直後時計 `2026-10-17T09:22:21Z` に、`company_allowance_identity_private` の `state`／`identities`／`history` と、`company_common_allowance_private` の `state`／`items`／`history`／`unit_aliases`／`requests` の8対象が全て `object_present=false` だった。`object_kind`／`rls_enabled` はNULLであり、存在しない表を「RLS無効」とは扱わない。対象schema自体の存在やその他の依存状態はこの結果だけで推測しない。pg_namespace/pg_classの定義存在だけを照会し、業務行・Auth情報・関数本文の取得、対象表/RPC呼出、変更は0。

clientは `read_company_common_allowances_admin` の会社・contract・version・can_edit確認前に編集を開かない。missing (`PGRST202`)、認可拒否、通信失敗で保存成功を表示せず、旧full-saveへ迂回しない。このfail-closedは既存機能保護であり、本番追加登録の完成ではない。

| 層／既存原本 | 適用する場合に扱うroot／関数 | 今回の判断 |
| --- | --- | --- |
| 前提 `supabase/migrations/20261009201229_company_allowance_identity_lifecycle.sql` | `company_allowance_identity_private` の `state`／`identities`／`history`、既存12 private helpers・5 public wrappers・3 settings triggers | 既存random UUID lifecycle。配備の有無・source/ACL/owner/triggerを別途照合し、番号だけで再適用しない。未配備なら独立の適用レビューが必要。 |
| #1152 `tool/staged_company_common_allowances.sql.review-only` | 新schema `company_common_allowance_private`、5表 `state`／`items`／`history`／`unit_aliases`／`requests`、新index、各表RLS・grants | 共通手当追加登録の最小server基盤候補。新表の直接clientアクセスは禁止。旧価格の別マスターを作らない。 |
| 同#1152：public wrappers | `read_company_common_allowances_admin(uuid)`、`save_company_common_allowances(uuid,text,bigint,jsonb,uuid,jsonb,jsonb,boolean)`、`read_company_common_allowance_request(uuid,uuid)`、`read_company_common_allowances_history(uuid,bigint,integer)`、`save_company_common_tax_settings(uuid,bigint,jsonb,numeric,numeric,uuid)` | 5入口は原本一式に含まれる。clientが使うのは共通手当read/save/receiptの3入口。税saveもDDLに含むので、手当だけのつもりで無断適用せず対象説明に含める。 |
| 同#1152：private helpers | `current_units`／`protect_unit_aliases`／`merge_unit_aliases`、`session_id`／`authorize`／`lock_writer`、`source`／`active_items`／`admin_state`／`request_result`／`save`／`history_page`／`save_tax` | account/company/role/current sessionとCAS・receipt・unit履歴を検証する13 helpers。publicはinvoker wrappers、内部definerは固定search_path。新role作成・既存Auth/provider変更ではないが、新権限面として承認対象。 |
| 同#1152：既存挙動への接点 | `public.my_attendance_allowance_units()` のguarded body replacement、`company_common_allowance_unit_compat` AFTER UPDATE trigger on `public.company_rate_settings` | 既存read RPCのOID/owner/ACL/SD/search_path維持が必須。価格を持たない旧名称→単位aliasを保持する。旧writerにも一部単位変更拒否が生じるため影響説明が必要。 |
| #1155 `tool/staged_company_rate_editor.sql.review-only` | private `rate_values`／`read_rates`／`save_rates`、public `read_company_common_rate_settings(uuid)`／`save_company_common_rate_settings(uuid,bigint,jsonb,jsonb,uuid)` | #1152 exact helper依存の追加5関数。#1234は旧4単価routeを維持し、この新APIを利用しない。手当追加登録を動かすため#1155を同時適用する必要はなく、別scopeとして保留。 |

## 固定する原本と保持条件

| 原本 | SHA256（今回offline実測） |
| --- | --- |
| `20261009201229_company_allowance_identity_lifecycle.sql` | `edacd1d8aac3ac0dd7219954192871725782369c82824173b2c73afe8aad3c3d` |
| `staged_company_common_allowances.sql.review-only` | `8f4c3b1b1cd07519174c88441c5e4b7eea325bbdd99b6ae455897b04e9786e46` |
| `staged_company_rate_editor.sql.review-only` | `5de4fe68e915b56c36edc4a3bf263da0140fa0bf5b9a5a0841903778034f6c23` |

main内の#1152 SQL blob `fd0bff09faba5caa2a88379ffff313366b5ba0ec` と#1155 SQL blob `44d7c1db34268a66bf98bef1e7eacfa6c5a8b9f7` は各最終候補の同ファイルと一致。再実装・SQL修正はしていない。原本guardが不一致なら停止し、guard削除・旧sourceへの巻戻し・番号合わせの再適用をしない。

旧3枠の現在値は `public.company_rate_settings.allowance_[1..3]_{name,amount_yen,unit}` のまま。readで採用・初期化・backfillしない。初回の明示確認付き保存で既存adoptを1回呼び、同じID/generationのlegacy参照と新extrasを同一transactionで保存する。未編集NULL/blank/空白付き名称・表示単位は原値保持、日単位支給への表示分類と表示単位文字列を混同しない。renameはID保持、削除はretire、再登録は新generation。給与形態ごとの旧3枠複製・名称名寄せは禁止。

新extrasはstable IDで一度だけ保持。company全体version＋旧source全体CAS、actor/company/request/operation/payloadに束縛したreceiptを使用する。結果不明時は再送せず既存journalからreceipt照合。保存済給与・請求・日報・署名・既存税/福利・4単価・会社/利用者/所属/role/providerを勝手に更新しない。追加項目の個別給与設定／数量／給与計算／明細への反映は別担当の未完工程で、本変更の成功条件に混ぜない。

単位aliasは採用時点からのprice-free互換で、採用前の履歴復元ではない。既に観測済みの同名単位を変える操作や、重複名winner削除で旧単位が変わる操作は22023拒否となる。旧full-save APIを使う端末にも影響する。旧API自体は削除されず、元からのtax-trigger等の挙動も残る。新APIのCASが全旧端末の動作を置換したとは説明しない。

## 既存検証証拠と限界

| Exact source／実run・job | 完了ログで確認したこと | 証明しないこと |
| --- | --- | --- |
| #1152 `36aae2be…`：`38932222009`／`117078794044`、raw checkout `1020ea8…`（36aae→792490） | PGlite＋実PG17同一原本、random-ID adoption/rename/retire、原値/alias/ACL/OID保持、tax UPDATE spy common=0/tax=1、履歴失敗rollback、receipt、5回の実lock wait・old/new CAS・待機中role/session拒否 | JWT claimsは合成。実GoTrue/DataAPI、実既存管理者/provider、実本番backup復元、PDF/実機は未実証。 |
| #1155 `64b24965…`：`38934175811`／`117085359104`、raw `719611d…`（64b→02cab） | PGlite＋実PG17、旧4列だけの更新、tax UPDATE0、旧UUID/alias保持、5回lock wait、tax/rates shared CAS、旧writer conflict、role/session拒否 | 同じく合成auth。#1234の手当保存にこの追加APIは不要。 |
| 同最終組合せの親contract再検証：`38934175813`／`117085358608`、raw `719611d…` | #1152共通contract・PG17 raceも再成功 | 新UI/clientの本番接続・本番適用成功ではない。 |

既存の隔離restore testは合成行をmemory snapshotし、元unit関数へ戻して新schemaをdrop/recreate・復元する試験。**実archive復元・本番rollback手順ではない。** fixtureの `DROP SCHEMA … CASCADE` を本番へ転用しない。sourceがGitで統合済み、CIが成功、UIボタンが有効、という三つは本番保存成功の代替証拠にならない。

## 次担当が揃える具体的な証拠（いずれか未充足なら停止）

1. **採用scopeを固定**：手当のための既存identity依存＋#1152一式を候補とし、#1155・新3tab tax/rates置換は別扱い。exact source/hash、既存body置換1件、trigger、新表・全grantsと想定影響をレビューする。上記3RPC・8対象以外の前提一致・既存objectとの衝突・必要extension/language/実行依存は未照合であり、引き続き読取で確認する。DDL変更は残る保護・承認条件を満たすまで行わない。
2. **保護する現状態のbackup**：実DBのschema/data/roles/ownership/ACL・NULL/default/column ACL/RLS・関数/trigger/sequence/依存を含む保護archive、旧unit関数完全定義、対象会社settingsと既存identity/history、給与/請求/日報/署名とその参照。既存user/company/master/所属/roleの同一性、Auth identities/session/provider/redirect、必要Edge code/config/secretsの復旧先、Storage metadataとbytesも適切な非公開範囲へ。credentials/個人値をGit・chat・CIへ載せない。限定hashやmigration履歴を完全backupに置換しない。
3. **実archiveの隔離復元と時点差**：既存 `RECOVERY_REHEARSAL_AND_APPROVAL_20261016.md` とP36の実archive禁止条件に従い、外部通信/通知/cron/メール/SMS/providerを遮断した新規隔離環境の実行コード/拡張/role依存を独立レビューする。synthetic成功を許可に読み替えない。実backup復元、backup後の現データ差・更新済みrecovery連絡先を解決し、現ID/会社/role/provider/旧設定と新旧帳票を比較する。今回実施していない。
4. **その復元先で適用・戻し方を実証**：原本guards/影響/lock timeoutを維持し既存値・ID・owner・ACL・RLS・triggerを前後比較する。元unit関数復元を先に行う依存順と、新schemaを使う保存済items/retired/history/receipt/aliasの保全を決める。新たな合法保存後のDDL削除は復旧ではない。nonemptyデータを捨てるrollbackや本番での演習は不可。具体的な戻し方は未確立。
5. **実boundaryと通常動作**：復元先で正規owner/admin追加・再表示・編集・削除、viewer read-only、他社/匿名/role取消/session期限・旧writer競合・結果不明のreceipt復旧を実JWT/DataAPIで確認する。旧税/福利/3枠/4単価、管理者の既存導線・provider login・旧帳票を比較し、旧単位変更拒否の影響を説明する。protected原値を壊して「検証成功」にしない。
6. **具体的な承認→限定本番反映→利用確認**：上記の結果、exact適用artifact、変更箇所、残unknown、停止/復旧条件を利用者へ示して明示承認を得る。この文書はその承認ではなく、今は要求もしない。承認後の配備確認・client schema/permission/read gate確認が揃って初めて、本番の追加登録を実操作で保存・再読取照合できる。#1234のRelease導入・実機確認・個別給与接続は別の完了状態として記録する。

必要3public RPCの不存在は上記root観測で確認済み。その他の本番依存状態・実backup・実archive復元・実管理者保持・実JWT/UI・具体rollback・影響承認は未確認で残る。R31の前回終了結果未受領というMac工程を本資料から迂回しない。本番write0、SQL/Auth/RLS/権限変更0、給与計算source変更0。

参照：`tool/staged_company_common_allowances_review.md`、`tool/staged_company_rate_editor_review.md`、上記原本3件、各専用CIの実ログ、`docs/security/RECOVERY_REHEARSAL_AND_APPROVAL_20261016.md`。文書追加だけを行い、既存SQL・fixture・計算・承認条件を書き換えていない。
