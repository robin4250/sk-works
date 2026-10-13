# LINE 保存履歴から正式月次請求書の下書きへ

第3段階の保存 quote を起点に、Master が過去の取引先・現場名・消費税率・現場ごとの法定福利費率を明示し、正式月次請求書の下書きを作成する。現在の会社税率、現場単価、取引契約単価、福利率は読み込まず、過去へ自動適用しない。率の空欄は未設定、入力された 0% は明示した条件として扱う。履歴の日付を 9/17 で制限しない。

保存された人工・残業・早出・手当数量と単価を使用する。現場ごとの保存小計へ入力福利率を適用し、その小計へ入力税率を適用する（既存月次請求計算の順序と丸め）。既存 `expense_cost_components` が返す対象月の承認済み・明示配賦済み登録経費もプレビューに表示する。経費は既存契約どおり税計算外で合計へ加算し、Master が取引先・全金額・登録経費を確認してから作成する。税率・契約条件の既定値は設けない。

## API と書込境界

- `line_historical_invoice_workspace(quote_id)`：既存 Master/会社/LINE group/請求権限を確認し、保存 quote、digest、同社の実取引先候補と作成記録を返す。内部未設定顧客の正規 marker は除外する。取引先を初期選択しない。
- `line_historical_invoice_preview`：quote digest、明示した現場・取引先・税福利条件を確認。現在の単価再計算をする `create_line_invoices` / `line_confirmed_invoice_components` は流用しない。保存 rows と rates から算出し、保存小計との一致を確認する。取引先情報・登録経費も fingerprint に含める。
- `create_line_historical_invoices`：表示 fingerprint と明示確認、固定 command ID により原子的に作成。`public.invoices` は `status=draft`、`automatic_calculation=false`。固定 rows/rates、quote ID/digest、入力条件、actor を snapshot evidence に保存。`finalized_at` / `approval_finalized_at` / 承認表は更新しない。
- 新規 private commands/links は RLS と直接 anon/authenticated 拒否。quote は更新しない。既存請求、会社・現場単価、取引先、給与、勤怠申請・勤怠実績は更新しない。
- 取引先ごとに通常の `InvoiceCloudPage(initialInvoiceId)` へ接続する。作成と承認・発行を区別し、既存の承認者、印影、番号、route 数量、経費確定 hooks を通す。

## 重複と競争

同社/取引先/月の既存請求期間との重なりを拒否し、旧 LINE 提出台帳も確認する。quote は全現場を一度に作成するため、同社 LINE group/月は一回だけ正式化する。別 quote や別取引先へ切り替えて同じ履歴数量を再作成できない。固定 command の再送は既存 receipt を返し、変更された payload は拒否する。請求書を通常の操作で削除しても作成記録は保持し、再送で復活・二重作成しない（invoice FK は追加しない）。

旧 stage2 と同じ customer/month invoice advisory → `public.invoices SHARE ROW EXCLUSIVE NOWAIT` 順序を使用する。group/月の advisory lock は追加しない。旧 stage2→bridge は旧台帳確認、bridge→旧 stage2 は private LINE receipt の限定 INSERT guard により拒否する。既存固定 command replay は旧 RPC の early return で INSERT guard に到達しない。通常の invoice/給与/勤怠 trigger は変更しない。経費 scope lock と対象 claim/choice の FOR SHARE も使用する。

## 検証と未確認

PGlite 実 SQL：明示条件必須・0%と空欄の区別、現在税率/単価/福利を変えても固定金額不変、登録経費変更拒否、同 command 不変再送、同 group/月の別取引先重複拒否、旧 stage2 receipt guard で transaction rollback、複数取引先の一部衝突時は全作成 rollback、既存全 function 定義/ACL/owner/search_path と invoice 9 triggers 保持、経費/route 確定拒否、quote 不変、給与/勤怠無書込、匿名・一般社員・直接 private 表アクセス拒否を確認する。

専用 CI は実 Postgres 17 で旧/新両方の勝者、異なる取引先 key でも共通 table NOWAIT が働くこと、同 command の並行再送、別 command の group/月二重作成、既存通常 writer の逆順 lock への非ブロックを確認する。Flutter は率入力と session 変更拒否/失敗再送の固定 payload を確認する。

本 migration は CLI `migration new` により生成。本番適用・実 LINE 履歴からの正式下書き/承認/発行・iPhone 操作は未確認。これらを合成テスト成功と混同しない。

参考：Supabase Database Functions https://supabase.com/docs/guides/database/functions と changelog https://supabase.com/changelog を確認。Data API 自動公開の変更を踏まえ、private 表は公開せず public thin invoker RPC のみ明示 grant とする。

## 作成後の登録経費変更

橋渡しで作成した未確定・未承認・未編集の下書きに限り、「登録経費を確認・更新」で新しい経費と合計を確認して更新できる。作成直後の請求書保存行 fingerprint を private link に保存し、手動変更・部分承認も拒否する。人工・単価・税率・福利率・履歴証拠・取引先・印影は再生成しない。更新は経費 snapshot と税込合計のみ。company→invoice 行順と既存 invoice advisory/table NOWAIT、expense scope/claim locks、既存 invoice hooks を保持する。確認後の経費変更は stale fingerprint で拒否。同じ更新の再送は固定結果を返す。通常請求書・過去 quote・給与・勤怠は変更しない。
