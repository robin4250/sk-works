# automatic draft一件の再計算候補

基準main bedac66a。新規review-only SQLと合成verifierのみ。給与NULLカテゴリー修正の既CLI migrationを別入力として再利用し、ここではrefresh関数本体を変更しない。本番適用・本番行更新・実JWT・実API・個人情報・UI接続・自動通知送信は0。新APIと権限面の本番導入は明示承認までHOLD。

## 既存機能との違い

給料一覧workspaceと本人明細はSTABLE読取で、開き直しで再計算しない。条件・勤怠・契約を意味なく保存する迂回はしない。既finalize APIは再計算が不要なら確定まで進むため流用しない。今回の候補は一つのstatement ID、会社、worker、月初、expected revision、明示確認、expected source digestを必須にし、既auth/account/`payroll_settings_allowed(edit)`で正規セッションを検証する。サービスrole/JWT手書き・MCP auth偽装はない。

内部の非公開source digestは会社・worker・給与条件・月内勤怠/有給/調整・単位条件/数量・住民税解決結果・税条件・会社rate history・公式所得税表・payroll計算元・取引会社/契約を含む。業務原値を返さない。trusted preflightで取得したdigestとlock後に比較し、refresh/sync後も再比較する。源データdriftは40001で全transactionをrollback。会社全体の率履歴等は保守的に広く比較し、無関係な同会社変更でも停止する可能性がある。

**この候補にはsource digestを取得するpublic preview APIもアプリUIもまだない。** trusted preflightの読取結果を無加工で渡す前提であり、client単独で利用可能とは扱わない。digestはMD5で競合検知用、認証・改ざん防止署名ではない。原本保護には別の完全beforeとSHA256が必要。

会社KEY SHARE→worker UPDATE→会社率registry共有advisory→既`payroll_scope_private.lock_scopes`の月lock→statement FOR UPDATEの順。scope/revisionとcanonical月末、draft/automatic、finalized_at null、保存済みfinal documents不存在を検査。ロック後と計算後も現在権限を再確認する。既内部refresh＋attendance detail同期を再利用し、保存後も同一scopeの未確定draftでblocked=falseを必須にする。manual/finalized/snapshot存在時は拒否。新行の生成や13日勤怠補完、署名、税/保険条件の仮登録はしない。

## 副作用と保護

金額・detailが修正される場合は既実装どおりrevision増加、approved_ids解除、automatic_recalculation audit追加。現行detail同期は変更がなくてもupdated_atを更新し得る。応答changedはupdated_atを除くsemantic差を示す。繰返しでrevision/auditが増えないことを合成検証する。既review行は削除せず、古いrevisionの確認は新revisionの確認にならない。確定snapshot/history、元勤怠/条件/調整を更新しない。

本番の7給与triggerには月給正規化、控除計算、blocked guard、削除履歴帰属、印影、経費snapshotがある。合成fixtureは既正規化計算を再利用するが、本番の全経費snapshot/下流影響は完全には再現していない。本番副作用を0と断言しない。対象statement完全before、review/audit/final document・historyと必要な経費副作用対象、算出元・helper/trigger checkpointの保護が必要。現在実before未取得。コード差替えのbackupだけでは足りない。

## 検証・残る停止条件

`tool/verify_payroll_single_draft_recalculation.mjs` は既setup fixture/migration原典と別途保存されたNULL修正migrationを入力にする。旧NULLカテゴリーの保存済みdraft不整合を作り、既calculator＋syncの支給/控除/差引・detail、revision/audit、原本保持を確認。viewer/他社/匿名/確認なし/古いrevision/別会社・worker・月/manual/finalized/snapshot、expected source不一致を拒否。post-source driftは合成fault injectionでrollbackを確認する。実並行source変更の証明ではない。

```sh
node tool/verify_payroll_single_draft_recalculation.mjs /absolute/pglite/dist/index.js /absolute/reviewed_null_category_migration.sql
```

PGliteで正常・拒否・源データ前後drift・semantic再実行を検証済み。実PG17の二接続待機、既settings/rates/contract/finalizationとのlock順競合、権限取消待機、実JWT/HTTP、最新production helper/source完全一致、preview/UI、実backup・下流経費影響・明示承認は未達。協調しない直接writerや最終digest確認後の競合をguard単独で完全直列化するとは扱わない。native reviewが済むまで配備しない。

commit前の想定外変化はtransaction rollback。commit後のコードrollbackは給与行・auditを戻さない。後続の合法保存を壊す全行before上書き、revision巻戻し、audit削除は実装しない。訂正が必要ならexact afterと後続変更を再照合して別承認する。

## Native PG17 snapshot検証の候補

内部source fingerprintをVOLATILEへ変更し、READ COMMITTED以外のtransactionを拒否する。outer RPCのsnapshot固定を合成同一transaction検証だけで推定しない。専用native verifierは既syncの実UPDATEをfixture-only triggerのadvisory gateで停止し、実`pg_blocking_pids`待機を観測後、別接続が源表へcommitする。旧STABLEの実際の検知/見逃しを記録したうえで、修正版VOLATILEの源変更40001拒否・全draft rollbackを必須とする。source writerは保守的digestが含む取引会社行への非協調直接INSERTであり、ユーザー入力変更ではない。

別scheduleでは既public unit-conditions APIによるrefreshのrevision更新がcommitする間、候補をworker lockへ待機させ、古いexpected revisionが40001になることを確認する。fixture-onlyの異常注入trigger/関数はその使い捨てDBだけで除去する。専用workflowはreview用support branchのpush限定、PGliteとPG17のみ。PR/Flutter/iOS/本番への自動deployを追加しない。native成功が得られるまでは未実行として扱う。

初回native実行ではPGlite/PG17単独検証、旧STABLE・修正版VOLATILE両方の実source待機/commit後drift拒否が成功。CAS用の直接settings UPDATEは既fixtureのauthenticated table権限で拒否されたため、権限を増やさず既 `public.save_payroll_unit_conditions` に置き換えた。これは合成fixture内の明示条件変更で、本番で再計算だけのため条件を保存する案ではない。

## 実行済み結果（2026-10-19 JST）

source `92a26e089755326b9f5cebefcc6d6dcbd38a05c7`／tree `a149f6e425f75f609951e3417bace85a08cd84f4` の専用run [39171521335](https://github.com/robin4250/sk-works/actions/runs/39171521335)、job `117805394792` は成功。PGliteと同一fixtureのnative PG17正常/拒否検証が両方成功し、二接続の実statement lock待機後の別接続source commit→40001全draft rollbackをSTABLE controlとVOLATILEの両方で確認した。このPLpgSQL statement境界ではSTABLEもcommitを検知したため、「旧STABLEがこのscheduleで失敗した」とは報告しない。保守的にVOLATILE＋READ COMMITTED限定を保持する。

実worker lock待機→既public unit条件APIの保存/refresh/revision commit→古いrevision CAS拒否、REPEATABLE READ拒否も成功。Secret Scan `39171521338` 成功。初回run `39171416468` はCAS fixture writerのtable権限で失敗しており成功に読み替えない。

上記で「native未実行」は解消したが、すべての既settings/rates/contract/finalizationとの順序組合せ・待機中role取消、実JWT/DataAPI、productionの実before・最新helper完全一致・経費snapshot全副作用、public preview/APIクライアント接続は未達。限定source/APIレビュー段階であり、導入要求・本番適用・実明細修復完了ではない。

## 経費別紙captureの追加検証（2026-10-19）

既存の `20261010141814_expense_document_details.sql` からテーブル・実claims reader・実capture関数・給与triggerまでを無改変で読み込み、同じ再計算fixtureへ追加した。依存する経費表だけは、関数が参照する列を持つ合成表であり、実経費管理・消費ledger・Data API/RLSの全経路を再現しない。請求書/支払証明書のtriggerはこの給与限定試験には導入しない。

PGliteで実行成功。NULL区分の給与下書き修復、再実行、権限/対象/版/源drift等の拒否後に、経費申請原本と履歴別紙（captured_atを含む）が保持される。確定への遷移をtransaction内の正例として実行すると同じtriggerが実申請内容を保存し、その後の確定済み更新でも最初の別紙を保持することを確認し、正例自体をrollbackした。trigger未接続だから不変だった、という偽陽性を避けている。

専用support branchで既native PG17 workflowを自動実行する。新headのnative結果は別途記録し、先行headの成功で代替しない。製品SQL/API/アプリ導線の変更・本番照会/再計算・デプロイは行わない。全本番helper一致、実JWT、待機中権限取消、完全before保護と復元可能性、他の本番副作用の確認は引き続き必要。

Supabase changelogとtriggerの公式説明を確認。今回の合成試験はTLS/ltree/pgcrypto/btree_gist/custom operatorを導入しない。

## 待機中の権限取消を検証する追加schedule

native二接続テストへworker lock待機中と給与UPDATE内のadvisory待機中の2経路を追加。事前に認可されていた合成editorの会社membershipを別接続で削除してcommitし、待機解除後の42501拒否と給与行・audit・経費snapshotの完全rollbackを検査する。合成membershipは検証後に復元する。実JWT/session失効、全本番認可helperの証明とは区別する。この追加headの結果は専用CIで確認する。
