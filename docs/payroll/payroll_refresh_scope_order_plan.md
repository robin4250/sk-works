# 給与refresh scope取得順の調査（未実装）

基準: snapshot d45c87c5、read-only取得原典2026-10-09。本番変更無し。

scopeは(cid UUID,wid UUID,月初DATE)で比較する。既存advisory keyはhashtextextended(cid::text||wid::text||month::text,0)。monthだけの昇順では従業員/会社を移す操作の順序を保証しない。

| 原典入口 | 現在のscope取得順 | 最小修正候補 |
| --- | --- | --- |
| attendance_refresh_payroll / attendance_sync_payroll_detail | old→new、会社/worker/月移動の順は未整列 | old/new tuple集合を先に昇順prelock、refresh/detailの動作は維持 |
| paid_leave_sync_payroll_detail | old→new（refreshとdetail） | 同上、approved判定/給与条件を変えない |
| settings_refresh_payroll | 同new会社workerのmonth_start昇順 | 現状順を保持、raw複数行時の会社worker順は別問題 |
| ensure_monthly_payroll_drafts | company/worker昇順、単月 | 現状順を保持 |
| report_refresh_payroll | source_report_idのcompany/worker/work_date昇順 | 単入口は昇順、日報sign全transactionの後続新出勤集合は未取得 |
| sign_daily_report | report rowlock→status refresh→旧出勤DELETE群→report_workers無order INSERT/UPDATE群 | status更新より前に旧出勤と全新reportworker scopeをまとめてprelock |
| save_daily_report_signature | report rowlock後、両署名登録済ならsignへ委譲 | 同日報scopeprelockの最初の入口/rowlock順を共有する必要 |
| select_site_calculation_source | site設定UPSERT→work_date DISTINCT無order→worker DISTINCT無order | payroll対象の会社worker月全集合を先にprelock、invoice/payment側動作は別 |
| save_trade_company_contract | contract UPSERT→partner settings更新→site/output/date/worker DISTINCT無order | payroll対象全集合を最初にprelock、他帳票triggerロックは別調査 |
| resident schedule | 会社worker→resident header→対象month昇順 | 原典を維持。company gateを採用するなら会社rowより前に追加する必要 |
| snapshot finalize | company FOR UPDATE→worker→単月calc→PS | 原典を維持。company gate方式の後置は他入口との循環を作る |
| adjustment mutation | company/worker→旧新month昇順→adjustment row | 固定companyworkerのみ現契約で昇順、会社worker変更はraw privilegedのみ |

## 未解決のstatement/transaction境界

BEFORE row triggerはUPDATEでそのrowがlockされた後に実行され、任意multirow statementの全scopeを取得できない。old/newを各rowで昇順化しても、row1が上位scope・row2が下位scopeならtransaction全体は降順になる。transition tableはAFTER statementなので現在のAFTER row refreshより前に集合を取れない。行triggerの変更だけを「全statement deadlock解消」と称しない。

既知RPCの全scope事前取得と、任意raw bulk mutationの保証は分けて扱う。後者まで含めるには、bulk専用原子的入口か、company/global gateを全入口の最初に取る契約が必要。gateをcalculatorの途中に追加すると、residentやreviewが会社rowを保持してgate待ち、一方snapshotがgate保持で会社row待ちという新cycleを作り得る。会社profile/Authの既存動作へ無検証でgateを追加しない。

native PostgreSQL17複数接続で逆月・逆workerの出勤/有休、日報batch、現場/契約batch、調整移動、住民税schedule、snapshot確定の競合を試す。実advisory waitを確認し、timeout/deadlock以外の完了または明示競合拒否、review revision整合、既存給与/帳票結果・manual/finalized不変を検証する。PGlite単接続成功はロック順の証明ではない。

## Implemented bounded source stage

The isolated 20261009171504 migration validates exact original body hashes before replacing seven known trigger/RPC definitions. The internal helper acquires all company KEY SHARE locks, worker UPDATE locks, and canonical month advisory locks in tuple order. Signature entry points capture old attendance and current report-worker scopes before the report row lock and reject changed capture after locking. Site/trade payroll refresh uses the captured tuples; a changed collection after a wait fails with 40001. Invoice/payment certificate branches retain their original behavior and are fixture stubs, not verified calculations.

The new stage also checks the original review/confirmation company UPDATE locking definitions, changes finalization parent locks to company/worker SHARE, and returns saved finalized period/header, revision, workflow state and confirmation metadata. Draft self rows explicitly report draft/revision. Existing snapshot migration is unchanged.

Exact PGlite integration passes unknown-source refusal, original two-signature flow, helper privacy, saved snapshot/header/review independence, and draft state. A separate guarded PostgreSQL 17 workflow runs the same fixture and two-session reversed-worker signature serialization plus company SHARE/HR FK compatibility tests. Native results are pending CI; local PGlite is not concurrency proof.

This stage does not yet cover the seven attendance/leave mutation RPCs, destination draft replacement, worker-settings multirow updates, service-role raw bulk mutations, or a full transaction-wide lock guarantee. BEFORE row triggers cannot discover every scope of a later row. Reverse-month, full report batch versus adjustment/finalization, and mutation-entry scope-drift races remain required follow-up checks. No production application is authorized by these fixtures.

### Vehicle/signature lock inversion correction

The original vehicle RPC updated a report-worker row before its AFTER trigger updated the report header. Adding child SHARE after signature's report UPDATE would introduce the reverse parent/child order. This stage therefore includes the exact guarded private vehicle definition (152560f3e376eda1c0ae22e23bba34cb), acquiring the same captured payroll scopes and report UPDATE lock before any vehicle or report-worker mutation. Company membership, draft-only enforcement, active vehicle/route validation and odometer checks remain unchanged. Native fixtures execute actual vehicle and signature RPCs in both start orders and assert real lock waiting followed by successful commit. Local integration checks the existing signature-clearing trigger behavior; native results remain pending CI.
