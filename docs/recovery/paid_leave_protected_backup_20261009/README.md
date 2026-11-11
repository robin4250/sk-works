# 有給本番適用前の対象限定backup SQL（未実行）

基準source: main `a086828bb46819d74ca1bf9bd245e8f94a90dbdf`。このSQLは作成しただけで、本番接続・保存・適用・復旧は行っていない。実UUID・実金額・接続情報を含まない。#824のPG17組合せ検証とは別資料。

`capture.sql` は psql 用の雛形。scopeは管理担当が読み取りで確定した会社/社員ペアのJSON配列を、保護されたローカルparameter fileで `sko_paid_leave_scope_json` に設定する。空scope・NULL・不存在worker・必要関数不足・scope外scheduler候補があれば、出力を適用根拠に使わず停止して対象を再確認する。scope外候補は本番全体の新scheduler候補件数だけでなく、その識別子も保護ファイル内部へ保存する。単に現在のdraft1件だけをscopeにして他のleave-only/月給候補を見落とさない。

専用の秘密出力先（Git・CI・共有フォルダの外）をフォルダ700・ファイル600、umask077で用意する。接続は0600のpg_service/.pgpass等で指定し、URL/passwordをコマンドへ埋め込まない。psqlは `-X --no-psqlrc --set=ON_ERROR_STOP=1 --file=<保護parameter file> --file=capture.sql --output=<保護snapshot file>` とし、結果を端末へ表示・cat・teeしない。SQL文自体のechoも無効にする。rootが接続・scope・実列を確認してから実行可否を判断する。

同一REPEATABLE READ READ ONLY transactionで以下を取得する。

- 実有給target5、既存caller/guard6、approver resolver、導入済み角印helper/trigger/metadata/style RPCの全文・owner・ACL・search_path等。新有給helper/capabilityの不在も記録する。
- 対象表の列/既定値・CHECK/unique/FK・ACL/RLS/policy、既存trigger OID/定義/有効状態、角印3trigger、既存cronのcommand/状態、migration ledger。対象表のnormalization等のtrigger呼出関数の全文も保存する。新cronや設定変更はしない。
- 対象ペアの全期間給与明細の全行。manual/finalized/過去draftは比較保護用であり、更新候補ではない。audit/reviews/confirmers/payroll_adjustmentsも保護して履歴・確認状態を比べる。
- 当月＋保存明細期間の出勤（全行）・有給（日付/承認状態/識別子）、設定（全行）、会社締日/支払日/月ずれ＋新印影生成に必要な登録名/書体、workerのactive/affiliation/hire_date。
- 当該会社のpayroll計算元選択を全件、参照trade contract全行、trade company全行（所属/存在を含む）。fingerprintは出勤行/設定行/契約行のほぼ全キーと会社全payroll選択を使うため、参加した現場だけ・金額だけに縮めない。有給の理由やworkerの氏名/連絡先は保存しない。

適用前にJSON parse・非空・scope_checks・件数・0600・checksum・対象全関数署名を検証する。実関数bodyとcapture時点のmainを比較し、旧fixtureだけで一致を推測しない。snapshot取得から時間が空いた場合、再取得し差分を確認する。READ ONLYは後続操作を凍結せず、このsnapshotとDDL適用の間に変更が入り得る。適用transaction内の再照合/lock方式は別途レビューする。

有給にはOFF gateがなくcapabilityは適用即1。既存cron/JST00:00と通常勤務/有給/給与設定変更の再計算を考慮する。設定変更triggerは過去の自動draftも巡回する既存挙動であり、対象当月だけが常に変わるとは主張しない。

復旧対象は今回置換する有給5関数と新helper/capability。導入済み角印3trigger・reader/helperは戻さない。DDL復旧と変更済みdraft金額の復旧は別で、正当な新勤務・承認・監査を保護して必要対象だけ判断する。この雛形は実行可能な復旧SQL、全DB/Auth/Storagebackup、復元訓練の成功証拠ではない。

通常の勤務/有給変更triggerはOLD/NEWの過去月にも作用する。このSQLは対象ペアの全保存期間を比較対象に含めるが、保存明細のない過去月やscope外会社/社員の将来操作を完全にカバーしない。backup範囲不足の運用を復旧準備完了とは扱わない。承認resolverの実定義がconfirmers以外を参照する場合、その入力を追加してから使う。trigger関数の間接呼出依存もcaptureした全文からrootが確認する。
