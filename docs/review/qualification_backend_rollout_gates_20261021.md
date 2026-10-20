# 資格保存写真backend：本番導入前の最小条件（読取レビュー）

対象はPR1311のbaseline/readinessと、その前提の管理保存写真candidate。参照worktree `sk-works-qualification-ci` HEAD `8b7e335cff62d902c475eaa37365187c7adc9bfb`、既main作業checkout `6bc6c540` の保存資料/実装を読んだ。remote最新状態を取得したという意味ではない。SQL実行・本番照会・変更・migration作成・fixture再実行はしていない。結論は**現状HOLD**。mobile adapterの完成だけでは以下のbackend条件を満たさない。

## 配備単位とguard

|段階|変更|保存sourceの照合条件|
|---|---|---|
|管理保存写真前提|queueにadmin_saved_photos列、非公開一回permit表/2 helper/登録済rowのUPDATE・DELETE guard trigger、管理関数、既router/photo承認への局所patch|router本文 `ed2f102b6b86342b657d659e039d5066`、photo本文 `7c79fa3388e9cba9408f8f5f3f097bd4` または `b31a93002c1877cad114273859fa65da`。既helper存在とworker.status参照を確認|
|ordered baseline|既管理関数の新prepare時、expected_photo_pathsを現在保存写真順とJSON完全一致させ40001拒否|管理本文 `02baf8c4d52adbbd3396ed3edfcdd713`、oldpathsアンカー必須|
|専用readiness|同管理関数にread action、既routerのdispatch追加|baseline後管理本文 `8db1b9ad7b141c6d132ae4252f363288`、router本文 `e1dd246978182b2baf5222bc7ef03cbf` を同TXで照合|

ファイルは `docs/candidates/qualification_admin_saved_photos_20261019.sql.review-only`、`qualification_admin_photo_baseline_20261021.sql.review-only`、`qualification_admin_photo_prepare_readiness_20261021.sql.review-only`。baseline/readinessだけを未導入serverへ適用できない。readinessは新prepareのCASを表明し、既capability2種を変更しない。既管理request同ID retryはoldpaths検査前に既request応答へ戻るため、既固定申請を新baselineで作り直さない。これをbaseline bypassとして新IDへ流用してはならない。

現review-only SQLはbody MD5と限られた存在/アンカー検査であり、production全metadata・依存意味論一致を証明する導入wrapperではない。適用前に原本fullcatalog（全pg_proc、definition、OID、owner、ACL、proconfig/security属性、comment）、table/column/default/constraint/index、trigger定義・順序・enable、RLS/policies、依存を保存し、全一致guardと期待適用後catalogを導入担当が準備する。未知差分・再適用は停止し、許可hashを増やして通さない。

## 依存closureと既writerの停止条件

最低限closureはpublic RPC wrapper→private.personal_qualification_submission→personal_qualification_photo_submission / admin_qualification_saved_photos / qualification_photo_submission_result、account_access_allowed→account_server_access_allowed、has_company_featureの現在意味論、auth.uid、会社所属/approval assignee、workers active enum、qualification_master、worker_qualifications、qualification_submissions、Storage参照保護helper/policies。SQL依存catalogだけでは動的SQL/外部clientを取り切れないため、ソースと運用入口も照合する。

新guardは写真だけでなくworker_qualificationsの**全実内容UPDATEと全DELETE**へ作用し、DB ownerの保守も例外にしない。timestamp-only no-opと初回INSERTは残すが、旧直接編集、管理metadata編集、退職・社員/会社/Auth削除のFK cascade、バックフィル、保守/cleanupを壊さないことを確認しなければ配備不可。管理metadata申請UIは未完であり、直接writerを塞ぐ代替導線がない利用範囲を放置しない。対象調査には既 `qualification_certificate_repository.dart` の正式row操作も含める。既photo approveと旧single-photo metadata approveはpermit挿入patchを必要とし、片方だけの配備は禁止。

owner/admin＋現在can_manage_people＋accountをprepare/submitで維持し、承認は現在独立reviewer、申請者の現在所属/account、active worker・同社master・旧全snapshot CASを維持する。manager delegateは追加しない。helperの本番NULL/OFF/actor意味論をstub成功から推定しない。新GRANT・Auth/RLS権限拡張は導入範囲に含めない。

## 保存済queueとStorage

列追加default falseにより既申請は従来dispatchに残る想定。ただしrouterには既経路にもaccount gateと自己承認禁止が加わるため、「旧権限動作が完全不変」とは言えない。既pendingの自己申請/同一reviewer、退職/停止/所属変更後の取扱いと正規の別承認者を確認する。既pendingを一括更新・cancel・再submit・再prepareしない。原本queue/正式row/写真履歴/Storage参照の保護と、既本人photo/metadata申請の取得・承認/却下・旧draft再開を確認する。

Storage policy/bytesの追加変更・写真物理削除・新uploadはない。submit/approveは保存済object存在を検査する。旧参照保護（`20261010222753_protect_qualification_photo_snapshots.sql`）と既photo submissionのStorage access関数/policiesが、変更前・previous・pending・approvedの参照を保つことを本番定義で確認する。PGliteの合成Storage metadata/権限は実Storage API/bytes・hosted RLSの証明ではない。

## 適用と復元の運用条件

1. 原本と依存closure、既writer/削除保守/既pending影響調査、実helper/RLS/Storage照合を完了する。原本・期待後metadataと未使用復元/使用開始後の復元方針を永続保存する。
2. 既native PG17 lock-order CIの**最新head実結果**を統合担当が確認する。旧資料の未実行を勝手に成功へ読み替えず、合成fixtureの限定scheduleを全競合安全とも言わない。baseline/readinessの既成功は繰り返し不要。
3. 既writer入口を外部で停止しin-flight RPCを排出した区間でのみ、guard付き原子的導入と適用後catalog照合を行う。停止/排出の仕組みは現candidateにない。mobile入口は専用readinessが不在/旧応答/例外ならOFF、fallback禁止。
4. 復元も全writer停止＋in-flight排出を前提に別途準備・隔離検証する。関数だけ戻して新admin pendingがrouterから読めなくなる状態、既承認済写真の巻戻し、permit/列/triggerの無条件DROPを禁止する。使用開始後は新queue/承認済正式row/履歴/Storage原本を保持し、互換読取または正規終結を設計してから復元する。オンラインundo安全は未証明。
5. backend確認後にmobileの永続CAS/readback、固定ID不明結果復旧、actor/company/target/背景ABA失効、明示submit/cancelと独立承認を接続しRelease実機で確認する。現backend候補の読取レビューは本番適用許可や削除機能完了を意味しない。

依拠した保存資料: `docs/review/qualification_admin_saved_photos_candidate_20261019.md`、`qualification_admin_capability_20261019.md`、`qualification_admin_photo_native_race_20261019.md`、`qualification_edit_approval_reuse_20261019.md`、`docs/candidates/qualification_admin_photo_baseline_20261021.md`、`qualification_admin_photo_prepare_readiness_20261021.md`、`qualification_admin_photo_ci_candidate_20261021.md`。
