# 有給給与契約の適用前確認・復旧条件

対象は PR #788 の `20261008200018_paid_leave_wage_contract.sql`。本資料は本番適用・rollout の実施記録ではない。CI成功、PDF生成・目視確認、main統合、実機導入、実操作、本番DB適用は別の確認である。#788を実機確認完了として扱わない。

## 依存関係

既存の会社給与・社員情報の適用記録は [payroll_employee_migrations_20261008.md](payroll_employee_migrations_20261008.md) を参照する。ローカルファイル時刻と本番migration versionは一致しない。古いmigrationをrename・再適用したり、ledgerを書き換えて揃えたりしない。

この契約は既存列と `rate_formula` / 帳票snapshot JSONを使用し、新規テーブル・列・過去データのバックフィルを追加しない。GPS・車両などの未適用migration群をまとめて適用する必要はない。

- `paid_leave_requests` の会社・社員・勤務日・承認状態と、既存の有給変更トリガー。
- `worker_payroll_settings` の給与種別、日給、月給、月給の日額基準、時給、`rate_formula`、既存給与設定変更トリガー。
- `payroll_statements` の自動計算判定・workflow状態・金額・revision・fingerprint・保存済み明細、勤務データと既存勤務変更トリガー。
- 既存のnamed支給・控除明細同期、重複勤務と有給の契約、未来勤務の月境界契約。
- `private.ensure_monthly_payroll_drafts(date)` を呼ぶ既存の定期処理。新しいcron登録は行わない。

本番の実定義と依存関係が期待するmainと一致するか、適用前に読み取りで確認する。保存済み給与明細の単価・内訳は現在の設定から推測し直さない。

## 適用前に保存するもの

対象会社・社員を限定し、保護された保存先へ次を保存する。登録データや接続設定を公開Issue・CIログへ出力しない。

1. 更新対象5関数の `pg_get_functiondef`、所有者、ACL、`search_path`：`refresh_automatic_payroll_internal`、`sync_payroll_attendance_detail`、`paid_leave_sync_payroll_detail`、`payroll_condition_warnings`、`ensure_monthly_payroll_drafts`。
2. 関連トリガーのOID・実行イベント・呼び出し関数・有効状態、既存cronの定義・有効状態・呼び出しsignature。
3. 会社・社員・有給申請・給与明細の件数、対象draftの金額・明細JSON・revision・fingerprint、自動／手動判定・workflow状態。manual/finalizedの比較用snapshotも保存する。
4. 読み取りcapability RPCの存在・ACL、適用済みmigration version一覧。新RPCはauthenticated限定、内部関数はanon/authenticatedから直接実行不可であること。

適用は別途判断する。本資料はDDL/DML実行の指示や承認ではない。ローカルPGlite・CI成功は本番既存データの全組合せを検証した証拠ではない。

## 適用後に確認する契約

- 日給は登録日給、時給は正の明示 `rate_formula.hourly_rate_yen` を優先し、なければ時給列の8時間分。手動有給額は0円を含め維持する。日給÷時間から時給を推測しない。
- 月給の有給内訳は保存済み日額×日数。基本月給へ加算せず、有給取得だけで基本月給を減らさない。
- 承認済みで当日以前の有給を対象とし、正の勤務実績が同日存在する場合は全日有給を重複加算しない。既存schemaは全日単位であり、半日有給は未対応。
- 有給支給をnamed項目として1回だけ表示し、その他支給へ重複計上しない。PDFの単価・内訳は保存済みsnapshotを使用する。
- manual、自動計算無効、draft以外のworkflow状態は自動金額再計算から保護する。定期処理は当月のみを扱い、過去月を一括再計算しない。
- 本番未対応ならUIは準備中として扱い、旧警告を対応済み表示へ変えない。

## 停止・復旧条件

manual/finalizedの金額・revision変更、月給への二重加算や有給だけを理由とする減額、named有給とその他支給の重複、トリガー重複、想定外のACL・警告・対象月変更を検知した場合は、適用または運用を停止してbefore snapshotと比較する。

関数の復旧は、保存した実定義・所有者・ACLを基準に、トランザクション内で更新5関数を戻す。既存トリガーそのものを削除・再登録しない。新capability RPCを撤去または無効化してUIを未対応扱いへ戻し、新private helperは依存関数を戻した後に撤去する。旧migrationの再適用で代用しない。

**DDL復旧と、適用後に変わったdraft金額の復元は別作業である。** 関数定義を戻してもdraft金額が自動で元に戻るとは限らない。snapshotとの差分・適用後の正当な勤務や承認を確認し、必要な対象draftだけの復旧を別途判断する。manual/finalized、承認履歴、新しい有給申請を含む一括rollbackは行わない。

本番適用・復旧実行・iPhoneでの有給操作確認・TestFlight公開は、この文書では未実施として扱う。
