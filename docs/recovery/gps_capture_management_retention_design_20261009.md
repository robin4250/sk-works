# v1出退勤原記録の管理修正時保持：設計と対照fixture

基準 main `a086828bb46819d74ca1bf9bd245e8f94a90dbdf`。本書とfixtureは実装準備であり商品migrationではない。本番接続・本番SQL・Auth/RLS・rollout変更は行わない。保持期間、会社/アカウント削除時の保存・消去、写真bytesの保持方針を決めない。

## 再現した既知欠落

既存 `force_manage_attendance(text,jsonb)` は日報メンバーを除去した後に、対象workerの `daily_report_id=対象日報 OR work_date=対象勤務日` の原記録をDELETEする。残りメンバーがない日報をDELETE、残員がある場合はdraftへ戻す。続いて日報参照または未リンクのJST勤務日条件で原記録をDELETEし、勤怠行削除・有給cancel/approved登録・修正勤務作成へ進む。

capture UPDATE guardはDELETEを止めない。既知欠落fixtureは勤務修正、有給切替、休み、削除で、元v1出退勤2行が消失することを再現する。日報を直接削除すると、既存 `daily_report_id ON DELETE SET NULL` が原記録の元日報参照を失わせる。これは保持保証成功ではない。

## 最小案と変更範囲

現在の勤怠管理・有給処理・日報削除を成功させつつ、削除/リンク解除前のv1原記録を独立private ledgerへ保存する。既存の有効勤怠テーブルに削除済み行を残す案は、現在勤務の照会・固定UUID再送・二重退勤uniqueの判定を変えるため、この案では採用しない。ledgerは生記録のUUID、全payload、元日報IDと削除前の日報snapshot、実actor、操作種別、記録時刻を保持し、最初の元記録を後続操作で上書きしない。

具体的な商品変更候補は①新private ledgerと内部writer、②attendance_verificationsのv1 DELETE前とdaily_reports DELETE前の捕捉、③原記録参照を提供する既存日報読取導線、④既存写真orphan判定にledgerの参照を含める部分。public勤怠管理RPCの権限を広げず、写真bucket/RLS/認証を同時に変更しない。トリガーで捕捉する案は複数DELETE入口を漏らしにくいが、会社/worker cascadeも捕捉するため、その削除方針が確定するまで本番実装・ONしない。custom session変数やuser_metadataを権限根拠にしない。

帳票・給与の基準は変更後の正当な勤怠・有給とし、ledger原記録は監査証拠として分ける。原記録の元日報リンクを変えて保存済み給与や帳票を再計算しない。新archive書込失敗は同transactionの業務変更をrollbackし、原記録だけ削除される結果を防ぐ。

## 実行可能な対照fixture

`tool/verify_capture_management_retention.mjs` は既存capture verifierのsynthetic bootstrap SQLのみ再利用し、実mainのGPS勤務日・勤怠管理・capture migrationを読み込む。既存CHECK拒否/rollback assertionsは重複実行・実装しない。

`supabase/tests/attendance_capture_management_retention_assertions.sql` はbaselineの既知欠落再現後、**隔離fixture内だけ**で実験的private archiveとraw/report BEFORE DELETE writerを追加する。商品migration/復旧SQLとして使用しない。

- work/paid_leave/off/delete/report_delete の5操作が成功し、翌朝退勤を含む元出退勤全JSON、photo_storage_path、元日報全JSONが同値。
- 直接日報削除後の原記録再DELETEでも最初のsnapshotを上書きしない。
- archive書込エラーは原記録・日報・有給変更をまとめてrollback。
- 明示transaction rollbackは元勤務を残しarchive/新有給を破棄。

実験archiveには商品用RLS、immutable UPDATE/DELETE guard、actor/操作履歴、全削除経路制限、会社削除/アカウント削除方針、写真orphan保護、参照UIを実装していない。保存するphoto pathは文字列でありStorage bytesの存在・保持・復元は検証しない。本番全schema/全trigger/削除競合/新有給計算の全chain検証も別。

実行例（隔離PGlite、Node）：

```bash
node tool/verify_capture_management_retention.mjs /path/to/@electric-sql/pglite/dist/index.js
```

専用CIも既知欠落と実験対照のテストである。成功しても保持機能完成・本番適用・gate ON・iPhone操作完了を意味しない。
