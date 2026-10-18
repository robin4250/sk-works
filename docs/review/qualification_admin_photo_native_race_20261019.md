# 資格管理の保存写真：request/approve native競合fixture

基準local aggregate `131012ca`。既存候補のrequest-first修正 `57c70aa7` はsource-order/PGlite検証済みだが、実2接続待機は未実証だった。今回追加は新native test・専用workflow・本記録のみ。既存candidate/verifier/UI、製品SQL・本番・実Auth/Storage/RLS/権限・SDK・Macを変更しない。外部push/CI送信も担当外。

Supabase skillとPostgres best-practicesのdeadlock-prevention ruleを適用。request→advisory→qualificationという同じ順序を、ソース文字列の順序assertではなく以下の実DB scheduleで検査する。

## 原典再利用とschedule

`tool/verify_qualification_admin_photo_postgres_race.mjs` は既存qualification fixture schema/liveと既存migration3件を無変更で読む。既存 `verify_qualification_admin_saved_photos.mjs` のliteral setup blockもそのまま抽出し、変数展開や非literal化した場合は停止する。大きなfixtureコピーなし。3接続（setup/観測1、実参加者A/B）を使用する。

URLは `127.0.0.1` / `sko_qualification_photo_race_fixture` のみ。query/fragment/他schemeを拒否し、driver effective parametersもconnect前に確認。PG17、private/auth/storage schema不存在とpublic relations/functions空・他application schema不存在を確認し、既存schemaは削除しない。fixture内mock auth/RLSだけを構築する。roleが既存なら属性変更せず再利用する。

既存合成IDsで管理者Aが既存写真だけのrequestをprepare/submitし、正式rowとpending request全体を保存する。

- **負の対照**：同じ原関数のprepareにあるearly request lockだけを一時DB内で除き、late readだけをFOR UPDATEへ戻す。認可guardやapproveは改変しない。Bが既requestをFOR UPDATE保持→A prepare開始→`pg_blocking_pids(A)`にBが含まれる実Lock待ちを観測→Bが独立reviewerとして本来のapprove RPCを呼ぶ。**SQLSTATE 40P01必須**。timeout/auth/setup errorは成功扱いしない。両transactionをrollbackし正式rowとrequestが完全に元へ戻ることを検査する。
- **修正版**：原候補関数を戻し同schedule。Aのrequest待ちを観測後、B approve成功/commit→A prepare再開/approved返却/commitを必須とする。正式rowの写真順だけが承認どおり変わり、他欄を保持すること、受付は一つでrequested_by/reviewed_by/status/photo_pathsを保持しpermit漏れ0・Storage metadata2件保持を検査する。

10msは観測poll間隔だけで、sleep経過を順序成立の根拠にしない。待機を観測できない場合も失敗する。lock_timeout=10s/statement_timeout=20sは停止境界であり、timeoutをPASSにしない。

## 実行できた確認・未達

- `node --check` PASS。
- URL7種拒否がdriver import前、effective host拒否がconnect前であることをfake driver/subprocessで確認。
- workflow YAML、`postgres:17` service、固定fixtureDBを確認。既存lockfileの `npm ci --ignore-scripts` を使い新依存追加0。
- 負対照の関数がcompileし原候補へ正確に再installできることをTEMP PGliteで確認。既存PGlite verifierのbase/prepared-capability両lane PASS。これはSQL原典・fixture互換の補足で、実同時実行の証拠ではない。
- **この環境にnative PG17がなく、今回の40P01負対照・修正版2接続は未実行。** remote CIも未実行。rootが承認済み経路で送信後、専用PG17 jobが両方を実行しなければ完了扱いにしない。

実JWT/provider、実Storage bytes/API、hosted RLS、production適用や機能利用可能性を証明しない。review-only候補は本番未適用のままで、既存承認・backup/復元条件を緩めない。
