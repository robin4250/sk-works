# 経費方向v2の既定OFF導入SQLをオフライン準備する

`buildDefaultOffDeployment(before, candidate, expectedBusinessHash)` はSQL文字列を返すだけで、DBへの接続・実行・gate有効化・下書き変換を行わない。#1279の修正版review-only候補のSHA256 `770728fa45176d7bbeb77ebd0610f936659624e4b1287d63bd83e0dd9264fe5a` だけを受け付ける。`defaultOffBusinessHashSql`で事前に取得した金融5表のdigestを必須入力とし、導入直前の同じ5表のdigestと一致させる。保存済み対象rowもその集合に含む。固定された既存3関数の原典preflight hashと、生成後8関数のbody MD5を確認する。

## 生成SQLの保護範囲

- BEGIN／COMMIT内でlock_timeout 3秒・statement_timeout 30秒を設定。支払証明書と経費claim／精算選択／消費履歴／保存snapshotの5表を一括NOWAITロックする。稼働中writerがいれば待たず停止し、writer完了後に改めて準備・確認する。通常のSELECTは止めない。
- 導入前コードcheckpointの完全一致、全会社のv2/basis行不存在、converter・変換audit表・client rollout gate不存在を確認する。scopeは既存3関数・対応既存trigger・全event trigger。
- 既存3関数のOID／owner／ACL／設定／実行属性、既存trigger／event triggerを保持。新guard triggerは対象表・実行関数・有効状態・BEFORE INSERT/UPDATE/DELETE・行単位・無条件等を確認する。
- 新5関数のowner／search_path／definer／volatility／parallel／strict／leakproofと、全8関数のbody MD5を確認する。本番と同じpublic default EXECUTE（anon/authenticated/service_role）をfixtureへseedし、新public capabilityからPUBLIC・anon・service_roleを明示REVOKEする候補で検証する。新ACLの許可先はownerだけ。ただし既存所属・役割を検査するread-only capabilityのprivate/public 2関数だけauthenticated EXECUTEを許可する。PUBLIC・anon・任意のdefault privilege役割への追加EXECUTEは拒否する。既存3関数の権限拡張は行わない。
- direction gateのbodyはconstant `select false`。5表の全row JSONB digestを同じロック下で前後比較する。生成SQLに業務rowや個人値は埋め込まない。

## 検証

既存`setupExpenseCostFixture`と本来のmigration3本で合成DBを作り、v1確定済み帳票・消費履歴と、控除だけ非0の自動v1下書きを保持する。候補・事前金融digestの不一致、未知default privilege、v2/basis、converter、rollout、余分なgrant、設定・body・実行属性・既存/new trigger改変、経費row更新を注入して拒否とtransaction rollbackを確認する。成功導入後もv1の再計算で元row・revisionを保持し、既存`buildCodeRestore(before, after)`で元コードを完全復旧する。native PG17では別接続が書込table lockを持つ間のNOWAIT停止も実行する。

## 適用・復旧の制約

この変更はオフライン準備と隔離検証だけ。本番導入済み・実データ修正済みではない。正式適用では最新main・最新本番checkpoint・新関数追加権限を確認し、生成SQL全体を専用接続で扱う。エラー後は同じ接続で明示ROLLBACKしてから状態を再確認する。SQLの成功を確認するまで接続を他の操作へ再利用しない。競合する金融DDLを同時に行わない。

成功直後の実after checkpointを取得・保存し、既存code-only undoをその実before/afterから生成する。undoはv2/basis行、converter導入、未知のgrant／依存／metadata変更があると拒否する。適用後に別のrollout gate等を足した場合も、この復旧scopeでは扱わない。業務データの復元・変換取消とは別である。

OFFはgeneratorの分岐を制御する。DB書込権限を持つ者の整合したv2直接書込を全面的に禁止する境界ではない。旧client除外、実帳票変換、gate ONと本番利用確認は別工程として扱う。
