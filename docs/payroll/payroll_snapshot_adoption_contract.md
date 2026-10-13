# 給与計算条件と確定スナップショットの導入契約（未実装）

調査基準: main `c6b51faa2faa3aca30706336b08eee9b9f0df686`。追加照合: main `1dc5411e7db1f137d878e4ad8efc1609a3f097df` との `supabase/migrations`・`supabase/tests`・`tool/verify_paid_leave_wage_sql.mjs` の差分は0（2026-10-09）。Issue #273 の追加仕様を既存計算へ接続する前提調査。DB・Auth・RLS・既存アプリは変更していない。この文書と隔離テストは、税率計算や確定操作を実装したという意味ではない。

## 現在の保存と計算入口

- `IndividualPayrollSettingsRepository.saveSetting` は `worker_payroll_settings` へ `worker_id` conflict の直接 upsert。`loadSetting` は同表を読む。新旧クライアント互換性を維持し、保存済み固定金額を料率からの金額とみなさない。
- 既存の給与基礎条件は `pay_type`、`rate_formula`、`hourly_rate_yen`、日/夜/休日別の daily・overtime・early、月給/計算用日額。`family_monthly`・`transport_monthly`、`income_tax_monthly`・`resident_tax_monthly`・`social_insurance_monthly`・`other_deduction_monthly` は現在固定金額。`custom_earnings` / `custom_deductions` は name / amount_yen の配列で、直接金額入力との互換経路を残す。
- 最新計算器と出勤内訳は `20261008200018_paid_leave_wage_contract.sql` の `private.refresh_automatic_payroll_internal` / `private.sync_payroll_attendance_detail`。設定・出勤・承認済み有給・現場の計算元/契約を読み、JST当日までの実績を計算する。正の登録月給は出勤0でも支給する。有給は同日実働と重複支給しない。
- 公開相当の内部 wrapper `private.refresh_automatic_payroll` は `auth.uid()` の有無を確認し internal を呼ぶ。設定更新の trigger function `private.settings_refresh_payroll` は出勤月・既存明細月・対象月給者の今月を更新対象にする（`20261008040428_generate_fixed_monthly_payroll_without_attendance.sql`）。夜間schedulerは private internal を使用する。
- 月給 normalization は `20261008043151_align_future_attendance_monthly_payroll_boundary.sql`、追加支給/控除 normalization と月給内訳は `20261008045401_preserve_payroll_named_financial_details.sql`。新計算器だけ変更しても、これらが旧固定金額を再加算する可能性があるため、同一レーンで整合する必要がある。

## 再計算が止まる境界と不足

| 状態 | 現在の自動処理 | 導入時の扱い |
| --- | --- | --- |
| automatic=true、workflow_state=draft | 設定/実績変更で再計算。fingerprint/金額/blockedの差でrevision増加、approved_idsを空にし監査記録 | 新マスターの適用済みversionもfingerprintに含め、再確認を要求 |
| automatic=false | 計算器/内訳/normalizationは対象外 | 既存手入力明細を勝手に移行しない |
| workflow_stateがdraft以外 | 同上。現在のfinalized fixtureでは全明細行が保持される | 新料率更新でも再計算/削除対象外 |
| レビュー確認済み、workflow_state=draft | 確認revisionと確認日時の記録はあるが、計算器の除外条件には含まれない | 「確認」と最終確定を混同しない。確定の状態遷移とsnapshotを同一transactionで設計 |

`private.finalize_payroll_review`（`20261008004129_payroll_assigned_confirmation_notifications.sql`）は `private.confirm_payroll_review_month` への委譲で、明細workflow_stateをfinalizedへ変更しない。最新のconfirm implementationは `20261008040303_payroll_confirmer_visibility_guard.sql` にあり、revision単位の確認を保存する。関数名だけを根拠に不可逆の給与確定が実装済みと扱わない。

現行detailには pay_type / rate_formula / hourly_rate_yen / 出勤・有給・支給控除内訳等が一部保存されるが、会社料率の適用済みversion、税額表版/行、標準報酬等の基礎、家族人数の自動/上書き理由は未保存。現行fingerprintも会社料率/家族マスターを含まない。`calculation_fingerprint` は変更検出用のMD5で、改ざん防止署名ではない。

repoの既存migrationだけでは worker_payroll_settings 基礎CREATE TABLEや全てのworkflow更新入口を確認できない。fixture schemaは実production schemaの代用証明ではない。確定実装前に実環境schema/RPC/trigger/grantsをread-onlyで照合する。現状のdraft-only guardは自動更新を抑止する条件であり、直接UPDATEやservice-role等の全面的なimmutable保証ではない。

## 接続箇所と保存契約（提案）

1. 同じ計算transactionで、適用済み会社料率、税額表、個別給与条件、対象期間の実績、必要最小限の家族情報を直接読み取る。取得候補料率は使用しない。料率から算出した控除金額をworker_payroll_settingsへコピーしない。
2. 計算器のfingerprintへ選択した会社料率version/適用期間、税額表version、会社共通手当version、個別条件version、対象実績、家族対象人数/override、住民税適用開始年月を入れる。未来の版を登録しただけでは現在の給与を変えない。変更済みの自動draftだけ再計算する。
3. detailに名前空間付き `calculation_snapshot` を提案する。schema_version、計算器version、対象期間/計算基準日時、各source ID/version/適用期間、採用した率（雇用は全体/従業員/会社別）、基礎金額、端数処理、適用on/off、各支給控除のbasis/quantity/unit_price/result、家族対象人数とauto/override、住民税月額/開始年月、所得税表年度/区分/参照行/扶養等、gross/deductions/netを値として保存。家族全プロフィールや不要な個人資料を複製しない。
4. normalizationとsyncがsnapshotの計算結果を独自に上書きしないよう一つの結果経路を定義する。旧明細はsnapshot無しでも現在の保存済みdetail/合計を表示し、新率で逆算して後付けしない。旧直接金額は `legacy_fixed_amount` として区別し、切替は明示的な設定操作とする。
5. 最終確定は明細行をlockし、対象revisionと必要な確認を検証したうえで採用snapshot・結果・確定者/日時・状態を原子的に保存。再計算と確定の競合を防ぐ。確認後に条件が変わった場合はrevision不一致として再確認を必要にする。
6. 確定後のPDF/一覧/詳細は保存済みsnapshot/resultを読む。現行取得RPCのworkers/settings/会社とのlive joinによるpay_type・表示名・支払日のfallbackも見直し、確定時点の計算ラベル/支払条件が後から変わらないようにする。訂正は履歴を残す別revision/訂正処理とし、元確定値を書き換えない。

## 隔離検証

`node tool/verify_payroll_snapshot_boundaries.mjs /path/to/pglite/dist/index.js`

PGlite 0.3.14 の使い捨てDBで既存 `verify_paid_leave_wage_sql.mjs` のsetupを再利用し、実migrationの最新計算器とtriggerを実行する。setup SQLは複製せず、runnerの既知anchorが変わればfailする。現在の確認API/実RLS/Storage/給与確定操作を検証するテストではない。

検証済み: 固定月給300000 + 家族2000 + 直接追加5000 = 支給307000、旧固定控除/直接控除6400、差引300600。draft条件変更ではrevision増加・approved_ids無効化。finalizedとmanualの既存明細は、設定/出勤/有給変更と明示refresh/sync後も行全体およびその明細の再計算監査件数が保持される。他月の自動draft生成監査は妨げない。

未完了: 料率master、税額表計算、家族人数計算、quantity式、住民税開始年月、最終確定transaction、snapshot schema/API/UI、実環境権限と既存確定データ照合。

専用CI: `.github/workflows/payroll-snapshot-boundaries-check.yml`。新runner/契約/上流runnerに加え、全migrationと共有SQL fixtureの変更で実行し、bootstrap依存の取りこぼしを防ぐ。Node 24のsyntax検査と `@electric-sql/pglite@0.3.14`（ignore-scripts）による隔離検証のみ。

## 追加の本番metadata照合（rootによるread-only）

明細のworkflow_state制約は legacy/draft/finalized。finalized_by/at、detail jsonb、revision default 1、automatic_calculation default false、approved_ids、calculation_fingerprintの既存列を確認。worker設定のfamily/income/resident/socialの固定月額はnumeric default 0 / NOT NULL、custom支給控除はJSONB配列。専用snapshot列は未確認ではなく存在しないため、上記はdetail内への提案とする。

明細triggerは `aa_monthly_salary_statement_guard`、`deletion_history_attribution_guard`、`guard_blocked_payroll`、`payroll_custom_money_guard`、`zz_company_seal_snapshot`、`zz_monthly_salary_detail_guard` の6件。調査はschema metadataのみで本番データの参照/変更を行っていない。installed RPC本文・実JWT・全grants/RLSの確認は未実施。metadataの一致を、確定経路の実動作や全更新経路に対する不変性の証明として扱わない。
