# NULL勤務分類による給与合計0：最小修正候補

基準main `bedac66af938989a9e9d314ee2d96cd01b831a01`。2026-10-19のユーザー指示に基づきWork側で給与コード修正の準備を行う。本番適用・実データ更新・Auth/RLS/権限変更は既存の承認条件を維持する。

## 修正範囲

`private.refresh_automatic_payroll_internal(uuid,uuid,date)` の従業員設定単価分岐にある `category:=a.work_category;` 1箇所だけを `category:=coalesce(a.work_category,'day');` へ置換する。NULL分類の単価参照を既存の日別内訳生成と揃える。明示済み分類、計算元選択、税条件、保険設定、PDF、登録内容は変更しない。

候補は既存関数body MD5 `2c5230eea880fe8cddbe60bc6c4c0782`、SECURITY DEFINER、固定空search_path、plpgsqlを前提として検査する。不明版はDDL前に例外。既存の `pg_get_functiondef` を使ったCREATE OR REPLACEで単一文言を置換し、関数body全体がその1箇所の差分だけになったことも同一DO内で検証する。所有者・ACL・設定・属性を新たに設定し直さない。給与row UPDATE、全件再計算、勤務分類のデータ書換えは含まない。

## 検証

既存 `setupPayrollScopeFixture` と保存済み税・給与unit migrationをそのまま再利用する。新verifierはPGlite専用で本番URLや接続情報を受け取らない。

- 親版の実関数でNULL分類2勤務を投入し、総支給0・保存済み基本給正を再現するnegative controlを維持。
- 候補適用後はNULLと明示dayの結果が同じになる。2日基本分・残業・早出を含む合成値でgross/netと基本給を検査。
- day/night/holiday/holiday_night × daily/hourly/monthlyの12構成を、親版の実関数を復元した結果と比較し、gross/deductions/net/detail完全一致を検査。
- 取引会社を給与計算元に選択した場合はNULL分類でも親版と同じ契約単価結果。
- finalizedおよびmanualの保存済みstatementをrefresh前後で全列比較し不変。
- 不明な親bodyを用意すると前提guardが拒否。修正後の関数bodyが1箇所置換のみで、所有者・ACL・proconfig・SECDEF・volatility・parallel属性も不変。

実行はPGlite 0.3.14の隔離DBのみで成功（exit0）。合成schema・permission helperを使用する既fixtureの限界は継承する。実本番JWT/RLS/Storage/native PostgreSQL競合・実機表示の検証ではない。実額・個人情報はfixtureにも文書にも含めない。Flutter SDKは使わない。

## 適用前に残る工程

最初はCLI未導入のためreview-only候補へ保持した。その後、一時npxの固定Supabase CLI 2.121.0で `--help` と `migration new --help` を読み（両方exit0）、正式に `supabase/migrations/20261018215043_fix_payroll_null_work_category.sql` を生成した。生成logのMigration createdと空fileを確認し、保護済みreview-only候補とbyte同一内容をコピーした。依存・lockの変更、CLI init/link/db接続はなし。verifierの既定対象を正式migrationへ切り替えた。

CLI生成プロセスの終了poll時、外部PostHogテレメトリ通信が自動承認レビューに拒否された。送信内容が不明で、隔離作業の承認は私的repository情報の外部分析サービス送信まで含まないとの理由。CLIを再試行せず、生成済みfileを使う安全な独立工程だけ継続した。生成成功logはあるがCLIプロセスの正常exitは未確認。本番適用は一度も行っていない。

本番への適用には現定義・依存/trigger/所有者/権限のバックアップ、既存の隔離復元・承認条件、正しい対象draft/会社/社員/月の固定、同じ給与条件の確認が必要。適用、対象draft再計算、実機確認、確定済みsnapshot不変の確認を別々に記録する。

保険条件未登録と不足日の日報原本は別工程。本候補は保険条件や保険額を追加せず、打刻だけから日報や署名・給与用勤務を生成しない。既存source再利用による最小修正であり、本番修正済みとはしない。

## 専用CIの追加

新workflowはこのmigration・候補・verifier・既存fixtureのPRとmain pushだけを対象にし、PGlite0.3.14とnative PostgreSQL17（pg8.16.3）の2jobを各15分で実行する。nativeモードはlocalhost/127.0.0.1、5432、sko_unit_fixture、fixture専用認証、query/hashなしのURLだけを許可し、接続後もPG17かつ空DBを要求する。ローカルでは不正URL8種がmodule読込/DB接続前に拒否され、分岐追加後のPGlite回帰が1回成功した。native PGはローカルにないため実在PG検証はremote CIの結果を待つ。Mac・iOSビルド・本番接続・手動CI dispatchは含まない。
