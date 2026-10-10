# 確定明細snapshotの原子的採用計画（source実装中、本番未適用）

基準: 住民税33ea8ac7、採用gate0f298a2c。旧確定をbackfillしない。

| 入口 | ロック順・採用条件 | 差分 |
| --- | --- | --- |
| 新finalize RPC | 会社FOR UPDATE→worker KEY SHARE→既存calculator会社/従業員/月advisory→statement FOR UPDATE | 明示確認、給与edit権限、expected revision、automatic draft、blocked無し、必要全review checked/confirmed同revision |
| 調整create | 会社/worker KEY SHARE→対象月advisory→INSERT | 確定scopeでは訂正経路未実装として拒否 |
| 調整update/cancel | 会社/worker KEY SHARE→旧/新月昇順advisory→調整FOR UPDATE | ロック取得前に読んだscopeを取得後再照合し競合時中止 |
| 住民税schedule | 会社/worker KEY SHARE→resident advisory→対象月昇順calculator advisory | 既存住民税採用sourceを維持、snapshotからresident header lockを取得しない |
| 既存月review confirm/cancel/確認者設定 | 会社FOR UPDATE→statement | 新finalizeの会社lockにより直列化、旧関数権限を変更しない |

calculatorのキーは`hashtextextended(company_id::text||worker_id::text||period_start::text,0)`。異なる新キーを追加して同scopeと称しない。settings/attendanceの既存triggerの複数月ループとraw privileged DMLは、実PostgreSQLの並列接続で別途検証する。PGlite単接続成功だけをdeadlock無しの証明にしない。

調整の現在採用集合（ID、表示名、direction、amount、effective date、active状態）が実際に変化した対象automatic draftだけrevisionを進める。note/updated_atだけの変更では再確認を要求しない。旧/新月を移動した場合は両月を昇順で更新する。既存calculator fingerprintが調整を含まなくても、次のrefreshでこのrevisionを旧値へ戻したり古いreviewを有効化しないことを実fixtureで確認する。

保存する結果はbaseと調整集合、調整込みgross/deductions/net、採用PS detail、実採用給与設定/住民税source、document metadata、会社/従業員表示名、schema/calculator version、確定者/日時。家族対象条件は未設定なので推測しない。会社公式料率・所得税表は未接続なので採用済みとしない。既存固定値はlegacy_fixedの由来を残す。

新確定の本人/管理読取はsnapshotのみから金額・文書値を組み立てる。旧snapshot無しの非draftは保存base/detailだけを用い、現在の会社・従業員・銀行・確認者マスターから過去値を逆算補完しない。会社印flagの保存は印画像bytes/URLの不変性を保証しない。

refreshでsource/revisionが変わった場合は`finalized:false`と再計算後revisionを返してdraft変更を保持し、再確認を要求する。例外でその再計算をrollbackして古いレビューへ戻さない。snapshot保存・workflow遷移・監査は同transactionにし、監査失敗時は全rollbackする。

## RPC・結果契約

`public.finalize_payroll_statement(p_statement_id UUID,p_expected_revision INTEGER,p_confirmed BOOLEAN)`。既存給与settings edit権限とaccount guardを再利用し、住民税の一般編集者をowner/admin限定へ狭めない。調整manage権限を確定権限へ流用しない。

成功は`{finalized:true,revision,snapshot}`。snapshotはschema_version/calculator_version/statement_id/revision/period_start/period_end/issued_at/company_name/worker_name/base_result/result/conditions/adjustments/document_metadata/detail/finalized_by/finalized_at。resultはgross_pay/deductions/net_pay、adjustmentsはID/label/direction/amount_yen/effective_date。再計算変更は`{finalized:false,reason:"recalculation_changed",revision}`。旧finalizedやmanual、revision conflict、確認不足は拒否。同じ新確定revisionの再試行だけ同じ保存結果を返す。

snapshot内部に保存した銀行値は本人明細（現在のworker.user_id本人一致＋account guard）のみが返す。管理workspace・finalize戻りのdetail.bank_accountは空{}、private rawtableは一般利用者に開示しない。現在の銀行値から過去値を補完しない。管理statement rowのcompany_name/worker_nameはsnapshot値。PDF側はrow会社名を優先する後続adapter変更が必要で、workspace全体の現在会社名を過去明細へ一律採用しない。

新documents/historyは会社/従業員/statement UUIDをlogical attributionとして保持しFKで会社削除を阻止しない。一般読取は存続statement/会社/workerに基づく既存RPC scopeからだけ取得する。削除会社にstale membershipがあっても元statementは本番FKcascadeで消え、snapshot raw照会は許可しない。保存期限や全postgres権限に対する改変防止は新設しない。API経由append-onlyと全権限DB管理者の操作可能性を区別する。

## 検証済み範囲と残る適用条件

PGlite0.3.14で既存resident calculator/normalization、本人/管理/metadataのread-only取得原典、PSの6triggerを結合。未知原典guard、actualworkflow legacy/draft/finalized制約、権限/anon/raw/account拒否、全review要求、調整revisionとnote no-op、通常refresh後revision保持、調整月移動の両月invalidate、manual除外、source変更時の新draft保持、監査失敗時snapshot/PS遷移rollback、idempotence、確定後調整拒否、master変更後本人row全不変、管理銀行抑制、旧final backfill拒否を実SQL検証した。

本番未適用。Supabase local DB/advisorsはlocalhost54322未起動なので未実施。fixtureのAuth/permission補助は明記したsynthetic prerequisiteで、実JWT/Storage/全professional invite/MFAを証明しない。実PG17複数接続の検証が必要。特に既存attendance UPDATEはold月→new月順であり、future→pastの出勤移動とpast→futureの調整移動はadvisory循環を生み得る。会社/worker移動も含む全scope(cid,wid,month)順統一を次stageで行うまでproduction適用しない。

現段階でPDF rendererはlive名前を使う箇所が残るため、DBsnapshotだけでPDF画面接続完了とは称しない。訂正revision/UI、印画像bytes不変性、使用公式料率・税額表の実計算接続、未設定家族対象条件は別未完了。旧値を新規則でseed/backfillしない。

確定入口はperiod_startが月初、period_endが同月末の正規月次periodだけを受け付ける。partial/non-month-start periodはadvisory取得・refresh・snapshot書込より前にfail closed。旧periodを推測して変換しない。非月初と短縮月末の拒否でPS/documents/history不変を実fixture検証。

## non-draft読取はlive計算を実行しない

旧live helperを全行で評価してからsnapshot値へ上書きする方式は採用しない。原典本文・認証・本人scope・manager visibilityを明示DDLで維持し、live helperには`workflow_state='draft'`の条件を加える。non-draftは別SELECTでPSと保存snapshotだけから金額・detail・表示名を取得し、live adjustmentsのSUM/cast、現給与settings、銀行値、document metadataの計算を通らない。管理workspaceもdraft集合と直接non-draft集合を合成する。top-level利用者権限/worker一覧や現在review状態の評価は既存どおりだが、給与結果/文書値の補完には用いない。

実fixtureで旧finalへ2,000,000,000円の後続active調整を2件登録し、旧本人/管理helperの`integer out of range`を両方再現。そのまま新読取へ切り替えて保存base net8,000円を正常取得した。新snapshot確定後master変更に加え、non-draftのlive metadata参照で必ず例外を出すfixtureを置いても本人/管理の保存結果を取得できることを確認。一般raw権限や会社scopeは追加していない。
