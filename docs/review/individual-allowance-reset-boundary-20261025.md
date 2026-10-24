# 個別手当の仕切り直し：対象確認と切替境界（2026-10-25）

## 現在の状態

ユーザーは「現在個別にあるものも一旦削除して、共有設定から再設定する」方針を承認した。ただし対象社員・個別追加の控除や家族手当等まで含むか・切替開始月はまだ具体化していない。この文書は実施仕様の準備であり、本番削除・金融変更は行っていない。共通登録が空／未公開のまま個別だけを消す操作は提供しない。

コード基準は main `22ecb36`。現行 source の saveSetting / save_conditions と本番の関数・RLS・trigger catalog を読取専用で確認した。今回の本番照会は catalog のみで、従業員・金融の業務行は取得していない。

## 保存先と対象カテゴリ

| カテゴリ | 保存先 | 仕切り直し候補 | 必ず保持するもの |
| --- | --- | --- | --- |
| 旧個別・日単位支給1〜3 | public.worker_payroll_settings.allowance_name_1〜3 / allowance_1〜3 | 同一会社の選択社員について、名前と額をペアで空／0へ正常保存 | worker行そのもの、他設定、過去の勤怠選択名、明細・PDF snapshot |
| 個別追加・時間／日／月の支給 | payroll_unit_private.conditions.items（section=earning） | 選択したIDのみを適用開始月の履歴から除外。全消しも選択明示が必要 | 前月以前の条件履歴、除外外のID、quantities、元IDのバックアップ |
| 個別追加・時間／日／月の控除 | 同上（section=deduction） | 支給とは別の対象選択。自動で全選択しない | 税・保険関連の条件と履歴 |
| 旧月額の追加支給／控除 | worker_payroll_settings.custom_earnings / custom_deductions | 配列内の選択項目のみ。名称だけで税や保険と判断しない | 選択外の配列項目と並び、他の原本 |
| 家族手当／交通費の旧月額 | worker_payroll_settings.family_monthly / transport_monthly（UIで追加一覧へ取り込む互換値がある） | 個別の区分として表示し、明示選択された場合のみ候補 | 未選択の値。custom配列と重複して見える場合は原本由来を区別 |
| 給与調整 | public.payroll_adjustments | 今回の個別「設定」リセットから除外 | 追加・控除・取消・承認履歴すべて |
| 社内共通の登録・公開条件 | company_rate_settings / company_allowance_identity_private / company_common_allowance_private の原本・履歴 | 削除対象に含めない。共通での再登録・通常の廃止操作は別工程 | identity / generation / publication / activation / 使用履歴 |
| 退勤・日報の選択および私的価格receipt | daily_report_workers / attendance_entries / company_checkout_allowance_private.receipts | 一切削除しない | 選択名・署名・receipt ID・価格snapshot・消費記録 |

基本給、給与形態、勤務単価、残業・早出等の単価式、有給、税率、税・保険・住民税の条件・金額・適用月、会社・本人・役割・ログインは対象外。テーブル行の DELETE で代用しない。

## 実際の保存副作用：ここが切替の制約

### 旧worker原本には「この月以降だけ」がない

IndividualPayrollSettingsRepository.saveSetting は現在の actor を保持して workers から所属会社を再確認し、RLSの効く worker_payroll_settings に worker_id conflict の partial upsert を行う。旧slotやcustom額自体には適用開始月の列がない。

本番で有効な AFTER INSERT/UPDATE trigger は次のとおり。

- settings_refresh_payroll → private.settings_refresh_payroll()、source MD5 `e54f70cde281b21c0947b29faba0cde8`
- payroll_settings_refresh_generation_setting_issues → private.refresh_generation_setting_issues_trigger()、MD5 `1c37f8d09f61d757d7326179789ddcb5`

前者は対象社員の「全勤怠月 UNION 全給与月」（条件により現在の月給月も追加）を巡回し、既存の refresh_automatic_payroll と sync_payroll_attendance_detail を呼ぶ。したがって旧手当の名前・額を空にする正常保存でも、**過去の未確定・自動計算給与が即座に減額され得る**。画面で未来月を選ぶだけでは未来だけの切替にならない。

確定済み／手動給与を既存計算が保持することと、過去の未確定給与も保持することは別である。trigger停止・RLS緩和・例外的なdirect DELETEは使わない。

### 単位別条件には適用開始履歴があるが、将来の別履歴にも注意する

本番で確認した関数は次のとおり。

- payroll_unit_private.read_conditions(uuid,uuid,date)：MD5 `acdfa10850bde7da5a5fd08afb33ea4a`
- payroll_unit_private.resolve(uuid,uuid,date,date)：MD5 `1fd9299ad8043cf6bd10f625ed026ff3`
- payroll_unit_private.save_conditions(uuid,uuid,date,bigint,jsonb)：MD5 `84cb553c6aff44fd3f7f6ac7fe5164c1`

条件は starts_on <= 給与月の最新行を参照し、月別数量は quantities に分かれている。save RPCに選択IDを除いた配列（全対象なら空配列）を渡すことは既存契約内である。元行を直接削除する必要はない。

ただし保存は開始月以降の全 automatic draft を再計算する。開始月に確定済み／手動給与があれば拒否する。同じ starts_on の既存行があれば上書きになるため、必ずその行全体をバックアップする。開始月より後に別の条件行が既にある場合、そちらが再び優先されて手当が復活し得る。全期間一括削除を単一 save で済んだことにしない。

月別 quantities は今回削除しない。元からあるIDを除いた後、再追加するAPIには既存ID照合があるため、単に元JSONを再送しても未知IDとして拒否され得る。**現行APIだけで元ID・数量ごと復元可能とは断定しない。**

### 正常保存を2回呼ぶだけでは原子的な切替にならない

worker設定と単位別条件は別API・別transactionである。前者だけ成功して後者が失敗した場合、あるいは保存間に確定／退勤署名／共通公開が起きた場合の状態を無視しない。画面でボタンを付けるだけでは一括リセットは完了しない。未知結果の再送禁止・readback照合を維持する。

## 実施前プレビューの具体仕様

1. **対象の固定**
   - 会社IDを1件、社員IDを明示選択。全社・他社へ自動拡大しない。
   - 対象社員が現在その会社に所属することをサーバーで再検証。
   - 区分（旧日slot／単位別支給／単位別控除／旧月額custom／家族・交通費）、開始月を明示。
   - 元ID／slot／section／unit／name／額／source／starts_on／version／updated_atで対象を特定。名称一致だけで削除しない。
2. **バックアップ**
   - 選択社員のworker設定行全体、対象conditionsの前後・将来行、対象quantities、計算・承認状態を含む給与のbefore snapshotとfingerprintを保存。
   - 承認・署名・receiptと共通identityの行／hashも保持確認用に記録。
   - 復元に必要な原本はprivate保管し、Issue等へ個人金額やログイン情報を貼らない。
3. **表示する件数**
   - 選択社員数、種類別の対象手当数、影響する条件行数。
   - 開始月前／以降それぞれの automatic draft 件数。
   - 除外する確定済み／承認中／手動給与件数。
   - 別会社・対象外・版変更・共通未準備・元ID不明等の除外理由。
4. **金額差分**
   - 各社員・月の before 支給／控除／差引と、提案後の値および各差額。
   - 過去未確定分への影響も隠さず別欄で表示。
   - 重複控除、未入力時間、保険・税条件不足等でafter計算不可なら「算出不可」とし、0円と見なさない。
   - 単なる金額の足し引きではなく、同じ対象・同じ入力原本を隔離環境の正規計算へ渡して比較する。本番で変更後ROLLBACKの疑似プレビューや架空の給与生成は行わない。
5. **共通設定の準備条件**
   - 選択社員の給与形態に合う登録名／単価／単位が揃っている。
   - 月次公開が必要な項目は対象開始月のpublication／activationが確認できる。
   - 退勤選択型のday/hour項目と月次共通条件を混同しない。publication件数0だけで退勤用typed選択が0と断定しない。
   - 時間単位の実労働時間sourceが未接続なら保留。8h×日数や経過時間で補わない。
   - 登録0／未公開／履歴欠落／取得失敗なら、旧個別だけを先に消さず切替未準備として止める。空給与を生成しない。
6. **再確認と有効期限**
   - プレビュー後のactor/session/会社/社員所属・permissionを再確認。
   - 元行version/hash、給与workflow/revision、共通原本generation/versionをCASで再照合。
   - 対象・版・承認状態が変化していれば再プレビュー。記録された同じ操作IDの未知結果はreadback照合し、二重実行しない。

## 権限と保持境界

現行worker設定は RLS enabled。authenticatedの閲覧は private.payroll_allowed(company_id,'view')、挿入／更新は private.payroll_settings_allowed(company_id,worker_id,'edit')、加えて restrictive account_access_allowed が適用される。private.payroll_settings_allowed は auth.uid() 非null、会社の給与権限、会社内worker所属を要求する。リセット用に権限を広げない。

単位別保存は既存 require_access(edit)・会社／worker row lock・給与月advisory lock・expected_versionを利用する。service roleで本人権限の確認を迂回したり、auth GUCを偽装して本番試験しない。

## 復元の具体条件

- 実行前の原本と、実行後に期待する行hash／version／対象IDを対で持つ。
- 復元前に現状態が実行後と一致し、以後の編集・承認・署名・消費・共通切替がないことを確認。相違があれば自動復元しない。
- worker原本だけの復元も全月再計算を伴う。確定化した後の差額を過去の帳票へ押し戻さない。
- unit履歴は元ID／starts_on／version／数量を維持する必要がある。未知IDをnew扱いで作り直して復元済みとは言わない。
- 現行APIで安全に復元できないケースは、対象行・前後hash・lock・権限・使用済み判定を固定した別の復元候補を隔離検証してから使う。この文書は実行SQL／undoSQLを提供しない。

## 今回のReleaseとの切り分け

既存候補を調査した限り、単位別 starts_on 履歴は再利用できる。一方、旧worker日slot／旧monthly金額を「過去未確定へ影響させず、任意開始月からだけ無効化」する既存契約は確認できない。

旧worker手当の新しい有効期間／廃止履歴モデルや原子的な移行RPCが必要な場合は、今回の給与Releaseへ大きな変更を混ぜず別候補とする。既存triggerを止めてその場だけ切り抜けない。

先に会社共通の再登録を完成し、具体的な対象社員／区分／開始月とプレビューを揃える。ここまで終わる前に削除済み・切替済みとは扱わない。
