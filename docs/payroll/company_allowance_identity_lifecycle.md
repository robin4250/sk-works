# 会社共通手当の旧3枠identity lifecycle（限定stage）

基準main c409e0c753af1b2b09c3b11e225ccabc219833fd、Issue #273最新を確認。
Supabase CLI 2.120.0で新migrationを生成。**本番未適用、UI/日報数量/給与未接続、製品完成ではない。**

## #840との関係

Draft #840 exact93c99d1の会社rate既存3枠を正とする方針を継承するが、company+slotからMD5で導出するIDは採用しない。本stageはその未解決置換境界を独立実装する。#840をマージ/適用する依存ではなく、そのextras価格/競合名案との将来統合が必要。proposal SQLをこのmigrationとそのまま連結して製品導入しない。extras UUIDとの全catalog統合、重複名境界、対象期間resolverは未接続。

## 正とするデータと操作

現在の名称・単価・単位は `company_rate_settings` の3枠だけ。private identity行には価格/名称を複製しない。historyのbefore/afterは当時値を保存する証跡であり、第二マスターではない。

migration実行時は既存企業からIDを作らず、金額/名称をコピーせず、数量を推測しない。管理者がadmin readのobserved_slots全3枠を確認して明示adoptする。途中の値変更は原値比較で拒否する。adoptでも会社rate・過去給与は不変更、非空枠のみ初回generation=1/ランダムUUIDを取得。既存同名3枠は別IDのまま保持し、名称で自動統合しない。

| 変更 | identity |
| --- | --- |
| 非空→別の非空名称（改名）・単価・単位変更 | 同じUUID |
| 非空→空白/NULL | 廃止日時・actorを保持、新selectorから除外 |
| 廃止後空→非空（別手当） | 世代+1、新UUID。旧UUID再利用しない |
| 同transactionで空にした後に別名へ再使用 | 2つの履歴。旧UUID廃止と新UUID生成が原子的 |

非空から直接別名を入れる旧client操作は**改名**として扱う。別手当への置換は必ず明示解除→新規登録。推測で改名を置換に変えない。会社idの付替は採用後拒否。会社が存在する間のsettings行DELETE→再INSERTは拒否し、旧会社削除cascadeは許可、private履歴はcascadeせず保持。削除済会社のRPCはmembershipが残っていても拒否。同じ会社UUIDを再作成してsettingsをINSERTする操作も履歴再利用防止のため拒否する（既存ON CONFLICT UPDATEは許可）。

## RPC/互換境界

- owner/adminのみadmin価格read・adopt・version付きslot保存。既存account guard/会社membershipを呼出し、既存認証helperを変更しない。
- 同社member/viewerのlabelsはID/名称/単位/generation/versionだけ。価格/履歴/raw tableは返さない。
- private tablesはRLS有効でanon/authenticated/PUBLIC直接grant無し。public RPCはinvoker wrapper、checked definerはprivate schema。anon/PUBLIC executeをrevoke。
- 未adoptのlabelsは明示未導入エラー。黙って名前から仮想IDを作らない。
- 新adopt/editorはcompany行→rate settings行の順にlock、新editorはexpected versionを照合。原典 `20260922020000_add_company_rate_settings_management.sql` の旧rate saverは会社UPDATE→settings upsert、旧units saverはsettingsだけを更新する。既存writer本体は変更せず共通table triggerを通す。旧combined saverの2 UPDATEはversion+2になるため、成功後は最終versionをreloadする。
- new slot editorは実既存列updated_by=auth.uid()/updated_at=clock_timestamp()を更新し、未選択slotの名称/単価/単位を保持する。adoptはmetadataも含め会社rate行を更新しない。
- 将来quantity/給与連携のlock順はcompany→worker→対象月scope→settingsで統一し、settingsを保持してからcompany/worker/月を取りに行かない。このstageはworker/月のmutationをしないためcompany→settingsだけ。旧units saver全面改変は行わず、新給与triggerを結合する前に旧settings-only経路との順序互換を独立検証する。
- 採用後の旧writerも会社scope/admin/account guardを満たさなければ拒否。service role/認証無しowner更新は新identity/historyを暗黙改変しない（adopt前の既存writerは不変更）。本番導入前に管理処理互換を確認する。
- history保存失敗は会社値・更新actor/time・version・ID生成/廃止も全rollback。
- admin history/identitiesは現在全件返却。次のUI接続前にversion cursor＋limitのページングと価格を含まない通常selector readを分離する（長期運用で全履歴を主画面に流さない）。

## 後続quantity/給与接続契約

quantityには永久UUIDとsource version、当時表示名/単位をworkerごと保存する。最新slot番号や名前で過去利用を解決しない。廃止UUIDの履歴は残るが、任意従業員へ価格履歴readを開放しない。過去日quantityへの価格適用期間と対象日resolverは次工程。旧金額/namesから数量をbackfillしない。

日報save/署名/attendance projection、同日複数現場の数量policy、gross/detail共通resolver、会社単価draft再計算、個人固有単価から明示共通参照、確定snapshot/PDF接続は**未実装**。給与確定DB/UIはこのstageで触らない。専用セキュリティ追加/Webなし。

## 検証と導入停止条件

PGlite専用harnessはmainの実既存3migration saverをreplayし、明示採用/初期backfill0/同名枠保持/改名同ID/廃止→新世代/旧client再利用/version+2/会社境界/価格非開示/account/anon/viewer拒否/履歴失敗rollback/過去給与fixture全field保持/会社削除cascadeと履歴保持を検証。PG17同harnessと2session実row-lock wait/stale edit拒否を専用CIで実行。fixture認可はsynthetic支持schema、実JWT/RLS/Data API端末操作は未検証。

本番導入前にeffective ACL/column grants、実全schema replay、会社削除/再作成（同UUID禁止）、旧初期設定writer、認証無し管理処理、#840統合、実ユーザーJWT・新quantity・給与snapshot保持を検証する。full migration deployはしない。新DDL/DMLは本番へ送っていない。

参照：Supabase https://supabase.com/docs/guides/database/functions 。changelog.md取得は検索transportがtext/markdownを拒否したため取得未完了。汎用PostgreSQL transaction/trigger/固定ACLを使用し、新API版依存機能は使っていない。
