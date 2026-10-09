# 有給給与の本番読み取り確認（2026-10-09）

基準sourceは main `0a9033eb1a48fc465c82ff33868f074df7b5e8c3`。対象は `20261008200018_paid_leave_wage_contract.sql` と既存の [適用・復旧条件](paid_leave_wage_rollout_20261009.md)。本確認では本番DDL/DML、再計算、設定変更を実行していない。個人の金額、氏名、会社ID、明細JSONは取得・掲載していない。

## 確認結果

SK WORKS本番は PostgreSQL 17.6。migration台帳に `paid_leave_wage_contract` は存在しない。`public.paid_leave_wage_contract_version()` と `private.paid_leave_daily_amount(jsonb)` も存在しない。個別給与設定の `supportsPaidLeaveWages()` は、このRPCが1を返す場合だけ利用可能と判定するため、現状は未対応扱いになる。

更新対象5関数は存在するが、新有給helperを呼ばない旧定義。`private.payroll_condition_warnings(uuid,uuid,date,date)` には「現在の自動計算に含まれていません」の旧有給警告が残る。実機画像の警告と一致する本番定義が確認できた。ただし画像だけからインストールsource SHAや特定明細の対応関係を確定することはできない。

**このmigrationには会社別のOFF gateがない。** 適用するとcapability RPCは即1を返す。既存の給与設定・出勤・有給変更トリガーが新関数を使い、既存cronも当月の対象自動draftを再計算し得る。「本番適用済みだがrollout OFF」という説明は、この有給契約には使わない。

本番aggregateは会社2件、社員8件、給与設定2件、有給申請2件（承認済み1件）、給与明細2件。明細は自動draft1件、手動finalized1件。`detail` に新契約識別子または有給支給額を持つ明細は0件。これを特定の利用者・会社の金額確認として扱わない。

## 関数の比較基準

すべて所有者postgres、SECURITY DEFINER、空search_path。以下は本番 `pg_get_functiondef` のMD5であり、復旧SQLそのものではない。

| private関数 | 定義MD5 | 本番ACL |
|---|---|---|
| refresh_automatic_payroll_internal(uuid,uuid,date) | 5f92398603ef2533c6111874794f6bcf | postgresのみ |
| sync_payroll_attendance_detail(uuid,uuid,date) | 1077ebd0e744bf559b140867e59b3773 | postgresのみ |
| paid_leave_sync_payroll_detail() | dc1da31becc7bf6c5a04a824d47cac24 | NULL（既定ACL） |
| payroll_condition_warnings(uuid,uuid,date,date) | d99616274ac0c5357a3f34196bca4818 | postgresのみ |
| ensure_monthly_payroll_drafts(date) | 83f0d7dc91162dbe0f780abe6f483fe8 | postgresのみ |

新migrationは有給トリガー関数の直接実行権限も明示的にREVOKEする。既存ACLを新ACLと同じだったと記録しない。今回は権限を変更していない。

必要列（給与種別、日給、月給、月給日額、時給、rate_formula、明細revision/fingerprint/detail/workflow、自動計算、承認済み有給日等）は存在する。`payroll_approver_ids(uuid)`、月給と追加支給のguard、給与設定・出勤・有給の既存トリガー呼出関数も存在する。存在確認は全定義の意味的同一性や本番全ケース検証を意味しない。

重要な既存トリガーはすべて通常有効（O）。適用後は同一OIDを維持すること。

| トリガー | OID |
|---|---:|
| attendance_refresh_payroll | 20921 |
| attendance_sync_payroll_detail | 28675 |
| settings_refresh_payroll | 20923 |
| paid_leave_sync_payroll_detail | 28677 |
| aa_monthly_salary_statement_guard | 28834 |
| zz_monthly_salary_detail_guard | 28836 |
| payroll_custom_money_guard | 28713 |
| paid_leave_refresh_generation_setting_issues | 28992 |

cron `payroll-confirmation-daily-jst` は有効、`0 15 * * *`（JST 00:00）。commandは `ensure_monthly_payroll_drafts` を含み、MD5 `0c29cad612ce5304210faafb8a46ba26`。新cronを追加しない。

## 隔離検証

基準mainの `tool/verify_paid_leave_wage_sql.mjs` をPGliteで実行し成功。合成データと既存guard/実トリガーのfixtureに対して、日給有給、時給×8、手動額0、月給の二重加算防止、承認取消、未来・未承認有給の除外、revision安定、手動額保護、approved明細保護を確認した。本番接続はしないハーネスである。

追加の隔離probeでは、手動finalizedと自動finalizedのそれぞれについて、refresh・detail同期・当月schedulerの実行前後で明細全行のJSONが同一だった。金額だけでなくrevision、fingerprint、detail等も変わらないことを確認した。これはPGlite合成fixtureでの証拠であり、本番PostgreSQL 17.6の全登録データを検証した証拠ではない。

## 適用前に残る作業と復旧

1. 直前の実関数5件の全文・所有者・ACL、関連guard、トリガーOID/定義、有効cron command/状態を保護された場所に保存する。この文書のMD5だけで復旧できない。過去のbackup branchを現在の実定義と同じだと推測しない。
2. 影響する当月自動draftを会社・社員単位で確定し、金額・明細JSON・revision・fingerprintと、比較対象manual/finalizedを保護された場所に保存する。公開Issue/CIログに出さない。今回このデータsnapshot保存は未実施。
3. 隔離PostgreSQLに現在の実定義・必要依存を再現し、migrationだけ適用した時点では登録行が変わらず、既存トリガー/cron経由では対象draftだけ更新され、manual/finalized全行が不変であることを確認する。PGlite結果をこの検証の代用にしない。
4. cron発火時刻と通常操作による再計算を考慮して適用時点を判断する。capabilityが即有効になるため、能力OFFで段階適用できるとは案内しない。
5. 異常時は、保存した実定義・所有者・ACLをトランザクションで戻し、新capability/helperは依存順に撤去する。既存トリガー/cronを削除・再登録しない。cronを変更した場合のみ保存状態に戻す。
6. DDL復旧と変更済みdraftデータの復旧は別。適用後の正当な勤務・有給承認を保護し、snapshot比較から必要な対象draftだけの復旧を判断する。一括rollback、過去明細の再計算、manual/finalized上書きはしない。

本番適用、既存明細再計算、新明細のiPhone操作確認、TestFlight公開は未実施。警告表示だけを消して有給対応完了にしない。

## 秘密を出さないbackupの実施方法（未実施）

バックアップはGit checkout、共有フォルダ、公開Issue、CI artifactの外にある暗号化済みローカル保存先で行う。フォルダ700・ファイル600、`umask 077` とする。接続は管理者が用意した0600の `.pgpass` と `pg_service.conf` で指定し、URLにpasswordを埋め込まない。`set -x`、接続設定のecho、SQL結果の端末表示を使わない。対象会社・社員UUIDはローカルparameter fileで指定し、ファイル自体をGitに保存しない。

`psql -X --no-psqlrc --set=ON_ERROR_STOP=1 --file=<保護したSQLファイル> --output=<保護した出力ファイル>` を使用する。SQLは `BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;` で始め、最後にCOMMITする。同じsnapshot内で、次のSELECT結果をJSON等に出力する。psqlに設定されている会社・社員UUID変数は文字列リテラルとして引用し、UUIDにcastして扱う。文字列連結でSQLを組み立てない。

- 定義保存：`pg_proc`/`pg_namespace` を対象5関数のschema・名前・引数で限定し、`pg_get_functiondef(oid)` の全文、`pg_get_function_identity_arguments(oid)`、所有者、proacl、proconfigを取得。関連guard・呼出関数も同様に保存する。コード定義とACLは現在の実値を保存し、既定ACL NULLを独自の権限に置き換えない。
- トリガー保存：対象4表の `pg_get_triggerdef`、OID、tgenabled、呼出関数OIDを取得。cronは該当jobのcommand全文・schedule・active・jobidを取得。cron commandに秘密値が含まれる場合も保護出力先の外に出さない。
- 最小明細snapshot：対象会社・社員の当月自動draftの全行を保存する。比較対象の同会社manual/finalized明細も全行を保存し、更新候補からは除外する。金額・detail・revision・fingerprint・workflow・approver/approved IDs・更新時刻が復元判断に必要。旧金額だけを保存して復旧可能としない。
- 計算入力snapshot：同じ対象のworker_payroll_settings、給与設定で参照する会社の締日/支払日/支払月ずれ、対象月の有給申請（識別子・会社・社員・日付・承認状態）、出勤、使用する現場/取引会社計算元・追加支給/控除の設定を保存する。氏名・理由・連絡先など、計算と整合比較に不要な列は除外する。ただし現行fingerprintが行全体を使う入力は、その行全体を保護保存しない限り同じfingerprintの再現を証明できない。
- 台帳・件数：migration version/name、対象別件数、関数/trigger/cron metadataを保存する。公開資料へは件数とcode hashのみ転記し、個人の明細hashやUUIDは転記しない。

出力後はSELECTの成功、ファイルが空でないこと、0600であることを確認し、同じ暗号化保存先にchecksumを保存する。checksumだけで元データを復旧できない。内容確認は保護環境内で行い、cat・teeで端末/CIログへ流さない。snapshot取得から適用まで時間が空いた場合は、再取得して変更差分を確認する。資料に手順を書いたことをbackup実施済みと扱わない。

## PostgreSQL 17隔離CIの具体的依存（未実施）

現行ハーネスのPGlite importを単純にpg接続に置き換えて本番URLを渡すことは禁止する。CIは外部到達不可のdisposable PostgreSQL 17 service、合成UUID・金額のみ、空DBで開始し、URLはlocalhost/service名だけ許可する。Supabaseの本番API key・password・snapshotをCIに渡さない。

既存 `tool/verify_paid_leave_wage_sql.mjs` のfixtureと適用順は次の通り。実DB検証では各段の失敗で停止し、同等のAuth role/auth.uid stub、public/private schema、pgcrypto/gen_random_uuid、invoice/payroll参照表・型を用意する。

1. `supabase/tests/invoice_stamp_approval_workflow.sql`、`payroll_private_bank_assertions.sql` と `payroll_pay_type_metadata_assertions.sql` のASSERTIONS前、`payroll_calculation_invariant_fixture.sql`。
2. `20261006162510_payroll_flexible_earnings_deductions_payment_day.sql`、`20261007021000_worker_monthly_salary_mode.sql`、`20261008001025_payroll_statement_pay_type_metadata.sql`、`20261008035104_stabilize_automatic_payroll_totals.sql`。
3. 合成paid_leave_requests、workersのstatus/affiliation/hire_dateを追加し、`20261008040428_generate_fixed_monthly_payroll_without_attendance.sql`。出勤夜間・夜勤/休日単価・手当列をfixtureに追加する。
4. `payroll_live_linkage_snapshot.sql` と既存4トリガー（出勤refresh/detail、設定refresh、有給detail）。本番から取得した対象関数・guard・trigger定義のcodeだけで差異を確認し、snapshot fixtureを本番相当へ更新する。個人データを複製しない。
5. `20261008042817_prevent_paid_leave_attendance_overlap.sql`、`20261008043151_align_future_attendance_monthly_payroll_boundary.sql`、`20261008045401_preserve_payroll_named_financial_details.sql`、rate_formula/hourly_rate_yen列、および本番適用済み旧警告 `20261008044613_payroll_financial_condition_attention.sql` の必要依存を再現する。現在のPGlite給与ハーネスは旧警告の全文までロードしないため、そのまま本番完全再現としない。
6. before snapshot取得後、`20261008200018_paid_leave_wage_contract.sql` のみ適用。DDL直後の全明細不変、capability=1/ACL、trigger OID不変を確認。cronはCIで登録せず、当月schedulerを明示呼出して同じ処理を検証する。
7. `payroll_named_financial_detail_assertions.sql`、`paid_leave_wage_assertions.sql` に加え、手動・自動finalizedの全行不変、当月自動draftだけの有給反映、過去月不変、旧警告から新条件警告への移行を確認する。保存した旧定義へ戻すDDL復旧も合成データで確認し、draftデータはDDLだけでは戻らないことを分けて検証する。

これは次の検証の実装仕様であり、PostgreSQL 17 CIの成功報告ではない。必要依存のDDL/ACL差分が未解決なら本番適用を止める。
