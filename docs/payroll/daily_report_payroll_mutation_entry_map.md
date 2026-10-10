# 通常日報mutation入口と給与更新対象

調査基準：main 0fafbc36、lib/features/daily_reports/daily_report_repository.dart、実原典 payroll-daily-ancestor-definitions.json（取得済み関数定義8件）。追加原典 payroll-daily-trigger-attachments.json で実trigger登録を確認。report_refresh_payroll本文のstatus差分条件はDB担当の実原典確認を併記する。全RPC定義・実行順序・actual JWT実行結果までは証明しない。以下「対象月」は給与refreshが呼ばれる場合に確認すべき report_date の月であり、refresh実行を推定して保証しない。

| 通常入口 | 呼出・直接変更 | company / worker / month境界 | refresh検証事項 |
|---|---|---|---|
| saveDraft | save_daily_report_destination_draft(report/site/route/date/description/workers) | 原典はauth.uidのcompany_members limit1で会社決定、destinationと全workerの同会社を検証。既存report同会社をlock。 | 旧/新report_date月、削除された旧workerと追加後新workerの両集合が対象。旧集合をDELETE前に保持する必要。 |
| worker追加・削除・時間/手当変更 | 上記RPCがdaily_report_workers全DELETE→指定workers INSERT | 同report内旧全workerと新全worker。追加workerはworkers.company_id検証。 | draft worker変更→署名clear→header UPDATEでtriggerは呼ばれるがstatus不変ならbodyは給与refreshしない。旧/新worker差分の給与反映は別source入口を確認。 |
| 既存signed日報の再編集 | approved edit requestを消費→report status draft、署名とsigned_atクリア→worker全置換 | 同会社report、申請者本人のapproved申請。旧/新月・worker集合。 | signed→draft時点のrefreshと後続worker mutationを別経路として検証。 |
| supervisor署名 | sign→save_daily_report_signature(role supervisor) | report IDと署名。会社/worker権限はこの8関数原典に署名RPC本文無し、未確認。 | status/署名更新に伴う全report workers・report月を確認。 |
| representative署名 | saveReporterSignature→同RPC(role representative) | 同上。 | supervisorと別role。署名が給与確定そのものとは扱わない。 |
| 修正申請 | requestEdit→request_daily_report_edit | reportID、reason。原典本文未収録。 | request row変更が直接report/payroll更新するか未確認。 |
| 修正承認/却下 | decideEdit→decide_daily_report_edit(approve/reject) | 原典はrequest.company_idと承認担当者を検証。複数承認担当者では自己承認不可。request/approvals/通知を更新。 | 実原典decide本文はrequest approved/rejected・approval記録と通知だけで、report UPDATE無し。承認RPC単独ではsource update無し。承認後save_daily_report_destination_draftがapproved requestを消費する時にsigned→draftとなり、status差分で給与scopeが生じる。 |
| 通常車両情報 | saveDraftのmeter未対応分岐→各worker save_daily_report_vehicle_usage | 原典はcompany_members limit1会社、draft report、既存report-worker、同会社active車両/route。車両積算距離とworker車両/route/km UPDATE。 | workers trigger→署名clear→header UPDATE→report_refresh_payroll呼出は確認。ただしdraftのstatusは変わらないため、この間接経路のbodyから給与scopeは増えない。 |
| meter車両連携 | meter対応分岐→get_report_vehicle_meter_context後、各event attach_vehicle_meter_to_report | report/sourceID、戻りworker/vehicle/date/event/kmをclientで照合。RPC自身の対象権限は原典未収録。 | event/source対象workerとreport月、既存署名/勤怠更新のtriggerを別途照合。 |
| 勤怠証跡添付 | link_daily_report_attendance_evidence(reportID) | report対象勤怠へのlink。latest本文の全境界は未確認。 | attendance側mutation→勤怠給与refresh経路を確認。 |
| group証跡添付 | attach_group_report_sources(report/anchor/sourceIDs) | clock-out済みworkersのsourceIDsをsort/deduplicate。戻りreport/source一致を検証。 | group sourceに属すworkerと実勤務月。report月だけで限定しない。 |
| route旅程添付 | link_route_journey_report(reportID) | routeAssignmentId有り時のみ。missing RPCだけoptional fallback。 | linkedjourney mutationと勤怠給与refreshの有無未確認。 |
| 保存通知 | publish_saved_group_report_notifications | reportID、保存通知retry時report company/updated_byを検証。 | 通知発行を給与計算更新と混同しない。 |
| 取消/日報削除 | このrepositoryにcancel/delete API呼出無し | 他の管理勤怠入口 force_manage_attendance(action/items)は存在。日報削除への接続は今回未確認。原典reject_direct_attendance_deleteはauthenticated/anonの直接勤怠DELETE拒否。 | 管理取消・削除の最新定義とOLD company/worker/month捕捉をDB側で別途確認。 |
| PDF添付資料閲覧 | loadPdfEvidence storage.download / signedURL | 読取のみ。 | 給与mutation無し。 |

## 間接workers→署名clear→report更新

実attachmentで clear_daily_report_signatures_on_workers はdaily_report_workers AFTER INSERT/DELETE/UPDATE、clear_daily_report_signatures_on_draft はdaily_reports BEFORE UPDATE、report_refresh_payroll はdaily_reports AFTER UPDATE全般に登録されている。従ってworkers→clear→report UPDATE→report_refresh_payroll呼出の接続は確認済み。

workers clear本文は coalesce(NEW.report_id, OLD.report_id) のdraft reportの代表/監督署名・署名者をNULLへUPDATEする。statusを変更しない。report_refresh_payroll本文はOLD/NEW statusが異なる時だけ給与処理へ進む（DB担当の実原典確認）。よってdraft車両/RW変更が間接header UPDATEを起こしても、それだけでは給与scopeは増えない。triggerの呼出とbodyによる給与refreshを区別する。

日報headerのsigned→draft等status遷移は別扱い。decide_daily_report_editの承認単独ではreport statusは変わらない。承認後save_daily_report_destination_draftがapproved requestを消費するsigned再編集でstatus遷移を含むため、更新時点の旧worker集合・旧/新月を確認対象とする。draft worker追加削除の給与反映をこのstatus-only bodyに頼れるとは断定しない。

原典 clear_daily_report_signatures_on_draft はdraftでdescription/site/date変更、またはlegacy signature_jsonを非NULL→NULLにした時、代表/監督署名をクリアする。署名NULL化そのものはstatus変更ではない。実JWTでの権限・対象scope・給与結果保持は未検証として残す。

guard_daily_report_shift_identity はcompany/date/site/routeの変更と既存shift証跡が重なる場合、勤怠管理からの修正を要求する。UIがdateを送れることは実際に旧/新月変更が許可される証明ではない。

saveDraftは単一client transactionではなく、最初の保存RPC後に車両・証跡・group・routeを順番に個別RPCで実行する。後続RPC失敗時、最初の日報保存済み状態が残りうる。個々の更新でsource refreshの冪等性・署名クリア・既存finalized給与保全を検証する必要がある。今回DB/UIの変更は行っていない。
