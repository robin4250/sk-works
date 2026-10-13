# 従業員ごとの住民税UI接続

ResidentTaxSection/Repositoryを個別給与設定の住民税枠へ接続。会社共通税率には置かない。月額と開始年月を専用の「住民税だけ保存」で保存する。一般保存popupにも別保存を明記。

採用gateがtimelineまたは確認不能の場合、一般保存のamount loopからresident_tax_monthlyを除外。確認済み未導入の場合は既存固定額入力・一般保存を保持。既存controllerは従来固定額の表示・復帰確認にのみ使用し、timelineで選んだ額はコピーしない。既存IndividualPayrollSettingsRepository.saveSettingはvaluesをそのままspreadしてupsertしており、欠落keyを0へ正規化するコードは無い。既存行に対する実PostgRESTのpartial upsertとproduction schemaの確認は未実施。新規従業員の旧固定額はDB既存defaultを使用する。

会社IDは選択済み給与設定のcompany_id、次にpayroll_workspaceのcompany_idを参照。どちらも無ければ対象workers.idから既存RLSでcompany_idを読み、取得不可はfailclosed。current membership limit1で会社を推測しない。DB read/saveは既存payroll_settings_allowedのview/edit・account guard・会社とworker一致を検証する。UIのcanEditは既存workspaceのeditをそのまま使用し、owner/admin専用に狭めない。

## 動作

- 初回state=nullと登録済みstate、取得失敗を区別。取得失敗は金額0のeditable defaultにしない。
- 今月（日本暦年月）のresolved amountと適用元を表示。0円は正しい月額として表示する。
- 新しい開始月は既存entriesを保持して追加し、同じ開始月ならその月だけ置換。最初のentryがcutover。未来登録後も今月のresolved旧固定額を表示する。
- 期間・旧固定額・履歴は折り畳み。actor/timeを確認可能。
- 保存確認は入力月・月額・全timeline開始月・開始前の旧固定額利用を明記。既存versionを条件に専用RPCで保存し、返却version+1／mode／cutover／全entriesを検査。
- 保存応答不明は成功と表示せず、同じ期待version・mode・cutover・全entriesを再読取で確認するまで追加保存を無効化。自動再送しない。
- 従来固定へ戻す操作は旧固定額・確認対象年月と未確定給与の再計算をpopupで明示。旧固定額そのものは変更しない。
- canEdit=falseは月額保存・固定額復帰とも無効。worker/会社/repository変更とmountedを世代番号で保護する。

専用DB migrationは別lane。本laneはDB/Auth/RLS・本番環境を変更していない。採用gate resident_tax_schedule_contract_version()の整数1成功でtimelineへ。PGRST202/42883のmissing RPCが確認された時だけ未導入として旧固定入力と通常保存を残す。通信・権限エラーや未知versionでは住民税編集を停止し再確認を表示、他の個別給与設定保存は継続。再確認応答はworker切替・load世代で保護。住所やmembershipから会社を推測しない。

## 検証

住民税section 10 tests（120件上限入力エラー・RPC0回を追加）、採用gate 3 tests（整数version、missing/その他error区別、一般保存対象）。既存9ケース: future cutover前旧額・開始後0円、同月更新と他月保持、対象worker会社解決、返却値不一致拒否、確認cancelと未来登録現額不変、view-only、取得失敗再試行、旧固定復帰確認、応答不明の再読取確認。

ローカルFlutter SDKなし。source reviewとgit diff --check実施、テスト実行はCIで必要。実給与の確定／未確定境界はDB laneのSQL fixtureが検証対象で、UI fakeを本番給与計算の証明として扱わない。
