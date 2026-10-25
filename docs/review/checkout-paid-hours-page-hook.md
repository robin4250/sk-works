# DailyReportPageへ組み込む最小hook（rootが順番に統合）

対象基準はPR1386の `checkout-report-gate-20261025/lib/features/daily_reports/daily_report_page.dart`。この候補は共有pageを変更していない。

1. `paid_work_hours_repository.dart` と `paid_work_hours_report_section.dart` をimport。stateへ `late final _paidHoursRepository = PaidWorkHoursRepository.maybeCreate();` を追加する。
2. 通常日報、保存済みreport/company IDあり、repositoryありの場合に、メンバー別cardの後・報告者サインの前へ `PaidWorkHoursReportSection` を置く。companyId/reportIdは保存済み `_report` から、workerNamesはそのreportの `_workers` から渡す。`sourceRevision: _report` で正規reloadごとにserver scopeを読み直す。routeVisitContextの別reportを通常reportとして渡さない。
3. onSavedで `_invalidatePendingSignature()` を実行し、署名ボタンをbusyにしたうえで `_loadSelectedSite()` をawaitする。個別のhours保存がサーバーの両署名を解除した結果を再読込する。ローカルに「署名済み」を残さない。
4. `_signReporter` / `_sign` 双方の既存 `final reportId = await _saveBeforeSignature(); if (reportId == null || !mounted) return;` の直後で、現在company/report/workerごとにrepository.loadを実行し `paidWorkHoursSignatureProblem` を確認する。problemありはSnackBar後return。RPC失敗を0時間/不要と扱わず署名を止めて再読込へ案内する。
5. 上記awaitの前後で既存 `checkSigningContext()`、`_report?.id==reportId` を確認する。actor/date/site/route変更時の既存拒否を保持する。署名を開く前にhours状態だけで署名済み・給与完了としない。
6. `repositoryForTesting` だけを使う既存pageテストでは、hours repositoryも明示注入するか、この追加server契約が無関係なfixtureであると明示して隔離する。productionでAPI未提供を黙って無視するfallbackを入れない。

通常の日報内容と勤務原本を先に保存し、hoursは別APIで保存した後に署名する順序を守る。二つのAPIを原子的保存済みと扱わない。途中失敗は元の日報を保持したまま未署名で再開できる。

現在の公開API候補は既存registrationのcurrent_actor helperへ接続し、同じUID/live sessionを確認する。NativeのJWT/GUCは隔離fixtureだけであり、本番actor偽装・本人セッション変更は行っていない。実GoTrue/PostgREST試験、本番導入・unused restore・実機確認は別途必要。
