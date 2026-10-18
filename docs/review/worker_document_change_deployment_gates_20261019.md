# 書類変更申請の導入範囲・既登録互換・削除影響・復元方針

この追補は既存書類候補を再利用して導入前の不明点を減らす。1243の候補SQL・UI・migration・本番を変更せず、独立した合成検証と適用計画だけを追加する。書類編集を本番で有効にしたという記録ではない。

## 今回減らせた不明点

`setupWorkerDocumentChangeFixture` に候補適用前で止める任意引数を追加（既定は従来どおり適用）。合成の登録済みfilled rowを候補導入前に作り、INSERT履歴がなくても、導入自体は既存会社・社員・書類項目・正式提出・履歴・Storage objectsを一切変更せず、同一rowの変更申請→別承認者による適用ができることを確認した。既登録filled rowにINSERT履歴を一括補完する必要はない。

これは未登録blank placeholderの初回例外とは異なる。空の旧rowに初回登録の正の証拠がなければ、候補は直接保存を拒否する。履歴を捏造するbackfillは行わない。その分類が実環境に存在する場合、ユーザーの既存登録状況の確認・正当な互換手順を別途決めるまで導入阻害として残る。

## DELETE/FK影響は確認済みの導入阻害

保存済み提出を持つ会社・社員・書類項目に対して、元schemaのON DELETE CASCADEを実行すると、新candidateの正式row DELETE guardが42501を返し、親DELETEも原子的に失敗する。特権で正式rowを直接DELETEしても同じ。さらに `auth.users` の既存 `updated_by ON DELETE SET NULL` は正式rowを更新するため、候補guardに拒否され得ることを合成検査で確認した。

失敗時に会社・社員・項目・正式row・履歴・Storage objectsが完全一致で保持されることも確認した。しかし「データを消さず拒否できた」は「既存削除機能と互換」の意味ではない。**会社削除・社員の物理削除・書類項目の物理削除・アカウント削除を既存機能として使う場合、候補導入によって止まる影響がある。現時点の本番導入阻害として残す。**

既存書類項目UIの削除は `WorkerDocumentRepository.deactivateRequirement` → is_active=falseで、物理DELETEではない。表示OFF→同一項目表示ONの往復は提出内容・写真を保持し候補guardに抵触しない。社員UIや会社・アカウントの物理削除までsoft化済みと推測してはならない。削除時に承認・退職履歴保存・匿名化・保存期間のどれを採用するかは別途の製品判断であり、この検証を理由にguardを無効化したりCASCADEを変更したりしない。

## 保存写真の権限source照合

保存済み `20260920205500_restrict_worker_private_documents.sql` のworker-documentsのSELECT/INSERT/UPDATE/DELETE policy本文を切り出してそのまま隔離DBへ再生した。全件許可のfixture policiesは除去し、既存multi-photo migrationのrestrictive retentionを残した。

本人は自分のworker prefix、管理者は権限がある同会社worker prefixだけをSELECTでき、別会社prefixは返らない。合成featureをOFFにした管理者は別社員写真を取得できない。承認で写真を選択から除外した後も、履歴に残る元photoは既存retentionにより管理者のDELETEから保持されることを確認した。新uploadや任意path差替えは追加しない。

`try_uuid`・feature helper・auth source・Storage objectsは明示した合成前提である。後続のrestrictive policy、account/realJWT、実ヘルパー・全RLS積層・実Storage bytesの本番一致を保証しない。既存本人/管理者の署名URLもこの保存prefixのRLSに従うため、候補導入のためにbucketを公開したり別policyを緩める必要はない。実環境のpolicy/helperが保存済みsourceと一致するかの照合は本番変更とは別の承認済み読取工程で確認する。

## UIを有効にするための限定適用範囲

既installed UIは既 `worker_document_change` の厳密capability応答が利用可の時だけ既存の申請操作を有効にする。本人/管理の申請、固定ID保存、再確認、承認一覧・差分のUIは既実装。資格saved-photoの別APIで有効化しない。新写真uploadも含めない。

既候補が作るものは、privateの申請queue・一回用適用ticket、snapshot/権限/結果/guard helpers、正式書類の追加BEFORE guard trigger、既存worker-document-retentionを補う参照、publicの変更申請RPCだけ。会社・社員・書類項目・既提出・既Storage objectsの一括UPDATE/DELETE、既RLSの緩和、Auth変更、給与変更は適用範囲外。

本番適用前に実catalogの対象table/column/constraint、既存policy/triggerと順序、helper定義・owner/ACL/search_path、RPC不存在、既存account/Storage経路の定義をexact checkpointへ保管する。書類書込を一時停止し、バックアップを隔離環境で復元して本候補を適用・検証する。書類データの構造分類（filled、正のINSERT履歴ありblank、証拠不足blank）と削除経路影響を確定し、未解決を残したまま適用しない。正式migration生成とsource公開、検証成功、本番承認・適用、利用可capability、実機申請・別承認者確認は別々に記録する。

## 復元・停止の方針

適用前checkpointには既定義とデータを両方含め、再現・復元を隔離環境で検証する。適用DDLは一つのtransactionに限定し、前提不一致・lock timeout・既存object衝突なら全体rollback。既候補内のBEGIN/COMMITも含め、実行経路がtransaction境界を弱めないことを事前に確認する。

適用後に問題が見つかった場合、最初に新規申請・承認を停止し、queue/票/正式内容/履歴を保持する。既API未導入に戻したい場合も、処理中・承認済み申請や正式変更を無視してDROP CASCADEや全データ巻戻しをしない。権限・public RPC・guardをどう停止/復元するかはcheckpointと現定義が一致する時だけ実行できるguarded手順を別途生成する。guard除去だけでは旧クライアントの直接更新経路を再び開くため、標準復元策にしない。

正式内容へ既に適用された正当な変更は自動で逆更新しない。差戻しには新しい承認申請を使う。pending/approvedのqueueや参照写真を削除しない。既productionバックアップ・隔離復元・承認条件を満たすまでは、本追補も適用許可にはならない。

## 検証記録と残件

新 `verify_worker_document_change_compatibility.mjs` をPGlite0.3.14で実行し、既登録filled互換、導入時data不変、5削除/FK経路の原子拒否、soft visibility復帰、保存sourceのStorage scopeと除外済写真retentionが成功した（exit0）。1243で済んだ10境界組とnative3競合を無用に再実行していない。この追補の互換・削除・Storage source検査はまだnativeで再実行しておらず、本番適用・実機を未完了のまま保持する。
