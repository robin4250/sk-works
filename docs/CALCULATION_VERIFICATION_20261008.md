# 登録データから帳票金額までの検証

勤務実績は `attendance_entries`、承認済み有給は `paid_leave_requests` を参照する。給与単価は社員別給与設定、請求単価は現場・取引契約、協力会社への支払単価は協力会社支払設定を参照する。給与原価と請求単価は異なる契約であり、同じ価格に上書きしない。

会社共通の給料日・支払月・締め日・確認者は会社設定だけを参照する。社員番号・所属・職種・入社日は社員データを参照する。本人プロフィールも同じ社員情報を表示する。給与閲覧範囲は既存権限を維持する。

| 対象 | 隔離PostgreSQLで確認した修正・期待値 |
|---|---|
| 給与の繰り返し計算 | 日給・時給・月給・手当・控除85項目。変更なしでは金額・版・実確認日時・履歴を維持。実績変更時だけ再確認 |
| 月固定給 | 登録30万円、出勤なし・有給のみ・最終出勤取り消しでも30万円。登録手当と控除は別途反映 |
| 請求月単価 | 月単価30万円・20日出勤は30万円。600万円に重複しない |
| 請求の直接単価 | 日額12000円＋登録残業2200円×2時間＝16400円。JSONの直接指定があればそちらを優先 |
| 支払証明書の時給 | 時給1500円・8時間相当＋残業1875円×2時間＝15750円 |
| 支払証明書の端数 | 日額10001円・2現場各0.5人工は明細5001円＋5001円＝10002円。保存合計と一致 |
| 早出・夜勤・休日 | 登録倍率・直接単価を使う。早出倍率1.1と残業倍率1.25を分けて検証 |
| 確定済み帳票 | 現在設定で金額を再計算しない。支払証明書は保存明細を使用。旧確定帳票に明細履歴がない場合は保存金額を表示 |
| 小数表示 | 倍率1.25・人工0.5を整数へ丸めて表示しない |
| 権限 | 閲覧範囲の不足したサブ管理者に全員分の給与確認を許可しない。設定済み確認者を自動削除・権限拡張しない |

再現と検証はCIから以下を実行する。テストは独立DBで実際のSQL関数・トリガーを使い、本番へのテストデータ投入は行わない。

- `tool/verify_invoice_approval_sql.mjs`
- `tool/verify_payroll_calculation_invariants.mjs`
- `tool/audit_payment_certificate_math.mjs`
- `tool/verify_invoice_calculation_sql.mjs`
- `tool/audit_payroll_empty_month.mjs`

## 未解決の金額方針

日給・時給の有給日数は取得できるが、既存コードには有給の支給金額方針が登録されていない。有給日数表示だけを金額計算完成と扱わない。

通常区分で入力する「夜間時間」は、社員給与設定に対応する時間単価がない。旧会社共通の夜勤時給は互換用と明示されており、勝手に新給与計算の既定値へ転用しない。勤務区分「夜勤」の登録日額・残業・早出とは区別する。

月給の夜勤・休日加算、手当の実績単位と日単位、日跨ぎ勤怠の対応付けはさらに検証が必要。以上を含む全組合せの金額検証完了や実機印刷完了を、この記録で主張しない。

管理勤怠の20時→翌5時退勤は翌日として保存し、出勤表では日報の勤務日に対応付ける。月末・年末、更新・削除、前日夜勤の保護、匿名・閲覧者・他社の拒否を実際のRPCで検証（`tool/verify_attendance_overnight.mjs`）。日報に紐づかないGPSイベントの夜勤対応は未完了。

連携検証は `tool/verify_payroll_live_linkage.mjs` で実際のテーブル登録・更新・削除と本番同等トリガーを使用。18項目で登録設定の反映、二重呼び出しの冪等性、金額変更時の確認解除を検証。有給・出勤の重複承認は拒否し、既存重複は実承認日時を保持したまま給与カウントから除外する。未来日の明細件数・時間を当日までの金額と混在させない。

実トリガー保存データから給与PDFを生成する回帰テストを追加。月固定給の補助値と基本給の二重表示、同じ控除の設定配列・旧キー重複表示を除外する。同名でも異額の独立項目は保持する。個別給与設定の無関係な保存で既存単価を書き換えず、旧家族手当は金額を見て編集可能にする。会社単価と手当単位は同一RPCで原子的に保存し、失敗時はどちらも戻す。計算元の選択は登録会社・現場・取引先を検証し、選択済みでも変更可能。支払証明書の単価は下請け支払設定を使用する。

## Additional isolated regression verification

The four additional PostgreSQL checks pass using PGlite 0.3.14: atomic company-rate/allowance saves roll back on a second-step failure; calculation-source choices validate tenant, party and role; financial-condition warnings are idempotent and preserve final history; real attendance/settings triggers retain named family allowance, duplicate-name deductions and non-day monthly base components.

Daily/hourly/monthly persisted fixtures reconcile named earnings and deductions with stored totals. Flutter PDF extraction tests must additionally verify the generated money rows; local Flutter execution is unavailable, so those checks are required in CI before completion. These new migrations have not yet been applied to production.
