# 住民税の年次確認と行単位更新候補

Review-only backend。既存 resident_tax_private.save_state / resolve と給与scope lockを再利用し、6月〜翌5月の12ヶ月通知額を保存する。税率から金額を推測しない。本番DDL/DML、既存設定の自動採用や年次確認は行わない。

## Client契約

`read_company_resident_tax_annual(p_company_id uuid,p_fiscal_year integer,p_request_id uuid default null)` は company_id/fiscal_year/current_month（JST給与月）/can_edit/scope_complete/snapshot/workers/complete/receipt を返す。workersは閲覧可能なactive employeeだけ。各workerは worker_id/name/amounts（June〜Mayの12整数）/current_amount_yen/source/confirmed/excluded/reason/confirmed_at/last_confirmed_at/schedule_updated_at。confirmed_atは現在sourceと社員cohortが一致する年次確認日時のみ、失効/未確認はnull。last_confirmed_atは過去の確認日時、schedule_updated_atは設定側server日時で区別する。

`save_company_resident_tax_annual(p_company_id,p_fiscal_year,p_expected_snapshot,p_entries,p_request_id)` のp_entriesは1件以上の任意subset。各行は `{worker_id,amounts:[12整数],confirmed:true,excluded:boolean,reason:string|null}`。対象外は理由必須かつ金額変更不可。通常行のreasonはnull。全員分のsnapshot CASを維持し、未送信社員の金額/確認receiptは更新しない。複数行を渡す場合は全件検証・原子保存。同request再送はactorとpayloadの一致を要求し、再計算しない。応答はrequest_id/company_id/fiscal_year/confirmed_count（今回件数）/保存後snapshot。同requestのreadは同actorかつ現在も全receipt対象の閲覧権限がある場合だけreceiptを返す。

年度外の既存予約・履歴を維持し、翌6月に変更点がなければ元resolver金額の境界を追加して当年度入力が翌年度を上書きしない。既存8月等の変更はreadの12配列へ展開する。saveは12ヶ月を明示した値だけ受け付け、UIは例外の同額化を確認してから送る。

## 完了と通知

内部 `resident_tax_annual_private.year_complete(company_id,tax_year)` が唯一の完了判定。clientへの直接EXECUTE grantなし。全active employeeについてその年度のconfirmationがあり、現在のresident state/legacy金額sourceと全社員id/status/affiliationのcohort hashが一致する場合だけtrue。前年同額/0でも明示確認receiptを保存するため完了にできる。個別保存・従業員追加/退職/区分変更後は再確認が必要。新cohortの一人だけ確認しても旧cohortの未送信社員は確認済みへ戻さない。通知側は未配備ならfalseとして扱う。

company lock→全worker順序lock→source再照合→給与scope lock→既存resident saver。確定/手入力明細は既存保存経路で保持する。非公開tableはRLSかつclient grantなし、公開invoker2本だけauthenticatedへEXECUTE。限定閲覧者には他者の名前/金額/source/receiptを返さず、scope_complete/can_edit/completeはfalse。

## 検証

既存の実給与/税/確定fixtureを利用。PGlite成功: 同額0年次確認、行単位蓄積/未送信日時不変、retry、source CAS、12月例外・翌年度予約保持、個別変更後失効、自動draft控除/差引再計算、手入力保持、不正金額/重複拒否、退職drift、限定閲覧、末尾batch保存失敗で全worker/履歴/明細/年次receipt rollback。PG17同検証と実2sessionでcompany lock待機中の退職driftをCIで確認する。

本番配備と既存backup/隔離復元、通知/UI統合、実機利用確認は別途必要。
