# 日報の会社共通手当を給与へつなぐ最小差分

読取調査のみ。基準sourceは `c6b51faa` の既存実装。PR840のproposalおよび
未公開quantity adapterは製品経路に接続しない。本書は本番migrationではない。

## 現在の実経路と確証範囲

| 段階 | 実装source／入口 | 現状と必要差分 |
| --- | --- | --- |
| 日報編集・worker別payload | `daily_report_repository.dart`: `DailyReportWorkerDraft.toRpcJson`、`save` | 各workerに `allowance_amount` と自由入力 `allowance_label`。会社master ID／quantity無し。ここに新形式選択配列を追加し、旧値を残す必要あり。 |
| 下書保存 | `20261003004500_complete_route_daily_report_flow.sql`: `save_daily_report_destination_draft` | report rowをロック、workersを削除して再insert。改行分割した手当名は最大3種類。新配列はworker単位で検証・保存し、旧client省略時に既存数量を消さない設計が必要。 |
| 初期互換保存入口 | `20260919220000_add_daily_reports_and_approval.sql`: `save_daily_report_draft` | 旧入口にもamount／label。存続／呼出実態を確認し、新形式を失わない互換処理が必要。 |
| 署名・実績化 | Flutter `sign`／`saveReporterSignature` → `save_daily_report_signature` | 本番read-only定義確認：public invoker wrapper→private definer。draft／member／role／strokesを検証して署名保存。代表・責任者の両署名が揃った時だけversion3 envelopeで `public.sign_daily_report` を呼ぶ。片方だけでは実績化しない。 |
| 確認済み実績化body | `20261003004500...`: `sign_daily_report` | `daily_report_workers`から `attendance_entries`へamount／改行由来namesを同期、`source_report_id`で所有を判別し対象行を更新。新quantityも同じ所有／shift同定境界で同期する。 |
| 編集承認 | `20260921220500_configurable_daily_report_approvers.sql`: `request_daily_report_edit`／`decide_daily_report_edit` | 後者は承認requestをapprovedにして編集可能通知を出す。承認そのものは新日報worker値の適用ではない。承認後再保存・再署名で数量を同期する必要あり。 |
| 出勤修正からの逆流 | `20261004081612_preserve_freeform_allowance_names.sql`: 承認済み修正適用 | attendanceの `allowanceNames`／`allowanceYen`を更新し、source日報worker label／amountも更新。新quantityを省略した修正で消去しない、変更時は同じmaster検証を通す必要あり。 |
| 管理者直接登録 | `20261008124940_gps_shift_work_date_evidence.sql`: `force_manage_attendance` | 日報workerとattendanceを同時upsert、namesは配列、日報labelは「・」連結、amountは0。別の実績入口なのでquantity対応を同時に必要とする。改行splitとの表記差も名前名寄せ禁止の理由。 |
| 給与gross計算 | `20261008200018_paid_leave_wage_contract.sql`: `private.refresh_automatic_payroll_internal` | `worker_payroll_settings`の個人 `allowance_name_1..3`を名前照合し、同日の同名をtokenで重複除外、個人単価を1回加算。会社rate単価を直接参照していない。ID×数量×会社単価の新形式branchが必要。 |
| 給与detail同期 | 同migration: `private.sync_payroll_attendance_detail` | attendance namesを `count(distinct work_date)` ×個人手当単価で集計。新形式数量に合わせgrossとdetailの双方を置換。detailのみ直しても給与金額は直らない。 |
| detail trigger | `20261006104144_sync_payroll_attendance_detail.sql`: `attendance_sync_payroll_detail` | attendance INSERT／UPDATE／DELETEから同期。bodyは後続migrationで上書き。draft＋automaticのみ更新する条件を維持。 |
| report status trigger body | 本番read-only `private.report_refresh_payroll` | status変更時、既存 `source_report_id` 実績のdistinct会社／worker／日をwrapperへ送る。初回署名ではstatus更新がattendance insertより先なので、これだけで初回gross起動を保証しない。 |
| 再計算wrapper／設定変更 | `20261008040428_generate_fixed_monthly_payroll_without_attendance.sql`: `refresh_automatic_payroll`、`settings_refresh_payroll` | wrapperはauth.uid無しではreturn、internalへ委譲。個人設定変更に反応。会社master単価変更による対象draft再計算入口は別途必要。 |

共通署名と旧signの連結は本番installed定義を読んで確認した（推測ではない）。
追加の本番read-only metadataでattendance gross/detailのattached triggerと各bodyを
確認した（下記補足）。初回署名のattendance INSERT、再署名UPDATE、削除DELETEの
給与呼出経路は定義上確認できる。Data API実JWT、delete guard通過、実ユーザーの
round-trip／結果金額は未検証なので、「全実行経路を実行試験済」とは扱わない。

本番read-only根拠（2026-10-09 JST session、ユーザーrow未取得）：
private signature MD5 `33f136b95542d8eaeb51167ec18cc4da`、public wrapper
`acb037e984efe9800318ec86aa936a4f`、public sign
`29d2c4ca53dba74aa30d8cecfd956320`、report trigger function
`de4b65bfde87a71776ebbd9c5fb538f4`。署名RPCbodyはrepository migration内の
検索で見つからなかったため、採用migration時にinstalled定義と差分照合が必要。

## ID＋回数を保存する最小の既存row

**第一候補は `daily_report_workers` の各(report_id, worker_id)行に新しい明示配列欄**。
要素は会社scope内のstable master ID、整数quantity、日報表示用名称／単位snapshot、
source identity/version。単価は従業員返却payloadに入れない。集団日報でもheaderに
共通数量を置かず、Aさん2回／Bさん0回をworker行ごとに保存する。UIは名前＋回数だけ。

**給与参照面は既存 `attendance_entries` 行へ新しい明示配列欄を同期**するのが
既存計算経路を保つ最小変更。`source_report_id`／shift identityを維持し、同一実績を
再署名で二重加算しない。管理者直接出勤・修正もこの配列に書く。両欄はsource日報→
実績projectionであり、手当単価masterを二つ作るものではない。JSONか別child rowsかは
DB担当のschema設計事項。本書は既存label／amountを転用しない。

同日複数現場／shiftの合算は数量を合計するのが候補だが、有無手当の「日ごと上限1」
と「実績ごと1」は別の給与ルール。masterに適用単位を明示し、既存の同日names token
重複排除をそのまま新quantityへ流用しない。選択配列省略＝旧client互換、空配列＝
明示解除を区別する必要がある。

## 従業員read境界

既存 `my_attendance_allowance_units` は会社memberチェック後に名称→単位mapを返す。
価格無しだがID無しで同名がcollapseする。既存 `company_rate_settings_state` は
owner/admin用で価格あり。従業員に後者を呼ばせない。

新member-scoped readは `id/name/unit`（必要ならactive/versionをenvelope metadata）
だけを返す。会社idをexplicitに検証し、金額のgeneric row serializationをしない。
既存rate tableを直接SELECT可能にするgrantは不要。scope・role条件は既存権限の
見直し作業と競合させずDB担当が扱う。新saveは返却名を信用せずIDから会社scope／
有効状態／unit／versionを再検証する。

## 名前と単価を一つにする際の明示移行

- **会社3枠**：現在会社dataのname／amount／unit列を正とする。別masterへ値をコピー
  しない。legacy IDは会社＋slot由来のidentityで、名前から生成しない。
- **個人3枠**：給与は現在この個人name／amountを使う。同名だから会社共通とみなすと
  異なる個人単価を失う。管理者に「会社共通参照へ切替」か「従業員専用追加へ保持」を
  明示選択させ、会社名への自動名寄せをしない。共通参照後は個人へ計算済み額をコピー
  せず、IDと適用条件のみ保持。直接入力式追加支給は別経路のまま。
- **日報自由入力と旧attendance names**：未解決の旧値としてそのまま保持。現在の
  個人名照合branchは旧row専用の互換処理に残す。quantityや会社IDを旧文字列・金額から
  自動推測しない。新明示形式と旧namesを同じ行で両方加算しない。
- **会社改名**：stable IDは同じ。未来selectorは新名称、保存日報／確定給与は当時snapshot。
  名称キー給与detailは複数ID同名で衝突するため、内部はID明細、表示集計は別にする。
- **廃止**：新規選択不可、保存済み日報は保持・読取可能。旧日報再署名で無条件に無効と
  して消さない。対象日の有効期間とrevision方針を定める。
- **3枠再利用**：空にして別手当へ再使用するとderived slot IDは同じ。quantity導入前に
  slot generation／永久ID保存＋廃止履歴などを一つ採用する必要あり。prototypeの
  deterministic company+slot IDだけでは「改名」と「別手当への置換」を区別できない。
- **会社単価変更**：対象期間のdraftだけ会社source revisionで再計算。確定給与は別DB担当の
  finalized snapshot契約に合わせ、後日price readで書換えない。
- **現場請求／協力会社支払**：`billing_allowance_*`、partner allowance設定は別契約単価。
  給与の会社共通手当に同名だけで統合しない。数量sourceを共有する場合もoutput別価格を維持。

## 最短で製品にする実施単位

1. DB担当：永続ID／廃止・置換履歴と新quantity欄、member-safe read、report／attendance
   save・署名／修正の一貫validation、会社共通source参照branchを一回の互換設計で決定。
2. 日報担当：price無しsourceを読込、worker別名前＋回数を表示、load／save round-trip。
   回数欄を付けるだけで旧APIへ送る変更はしない。旧自由入力値は読み取り保持。
3. 給与担当：grossとdetail、条件指紋に会社source versionを含める再計算、同日複数実績
   policy、finalized snapshot連携。旧rowと新row、承認編集、集団worker別数量、退役master、
   会社改名／単価変更、同名個人単価、0円非表示のintegration試験を行う。

未接続adapterや新たなprototype層を増やす必要はない。実際の保存／計算入口を上記の
最小範囲で揃えてからUIを接続する。


## 本番attached triggerによる署名後の実経路補完

根拠はrootのread-only `payroll-refresh-scope-metadata.json` と
`payroll-daily-source-metadata.json` のdefinition capture（ユーザーrow無し）。
DB担当が現在実装中のscope／snapshot変更前のcaptureであり、今後のinstalled body
が同一であるとは保証しない。以下は実行結果ではなく、実際にattachedされた定義の照合。

1. public署名wrapper→private署名関数はdraft reportをFOR UPDATEで取得し会社memberを確認。
   代表または責任者署名を保存し、両署名がある場合だけpublic signを呼ぶ。
2. public signはstatusをsignedへ更新。その時点でattached report-refresh関数が走り、
   **既存**source_report_id実績の会社／worker／日を再計算する。初回はまだ実績がなく
   空集合になり得る。追加catalogでreport側 `report_refresh_payroll AFTER UPDATE` attachmentも確認。status列限定triggerではなく、body内でstatus差異を判定する。
3. 次に古いsource_report_id実績のうち、現場／ルート／日が異なるもの、または日報から
   外れたworkerの行をDELETEする。全worker全行を毎回削除する実装ではない。削除前に
   `reject_direct_attendance_delete` BEFORE DELETE guardがattachedされており、通過の
   実ユーザー試験は未実施。成功したDELETEは旧会社／worker／日側のgrossとdetailを更新。
4. 各日報workerについて同じ会社／worker／現場／ルート／日／source_report_idの行を
   調べ、既存ならUPDATE、新規ならINSERTする。他sourceの同日同勤務先行は例外で
   transaction全体を失敗させる。数量追加もこの所有・競合チェック内に保持する。
5. attached `attendance_refresh_payroll` はAFTER INSERT／DELETE／UPDATE、row単位。
   INSERTはNEW、DELETEはOLD、UPDATEはOLDとNEWの会社／worker／日でwrapperを呼ぶ。
   wrapperはauth.uid無しならreturn、存在すればinternal gross計算を呼ぶ。署名member
   経路はauth.uidを確認済みなので、この定義上のINSERT経路が初回gross起動を担う。
6. attached `attendance_sync_payroll_detail` も同イベントrow単位。OLD／NEWに対して
   private detail同期を呼ぶ。同じAFTERイベント内ではtrigger名順で
   `attendance_refresh_payroll` が `attendance_sync_payroll_detail` より先になる。
   同一scopeのUPDATEではそれぞれ2回呼ばれ得るため、新quantity集計は増分加算せず
   sourceから再集計する既存方式を維持する。

同じattendance変更からinvoice、payment certificate、generation setting issuesも
再計算される。quantity採用時に給与だけのnames書換えで他帳票の旧names契約を壊さない。
site chat関係triggerはworker／site等指定列のINSERT／UPDATEなので、quantity-only
更新と実績再insertの副作用は同一ではない。既存guardやchat triggerは改変しない。

追加入口：worker設定INSERT／UPDATEのattached `settings_refresh_payroll` は実績月、
既存statement月、およびactive employee月給の現月を集め、gross wrapperとdetailを
順に呼ぶ。paid leaveのattached同期はOLD／NEWにinternal grossとdetailを直接呼ぶ。
monthly ensureは現月のみactive employee／月給または承認有給対象を内部再計算する。
会社master単価変更はこのworker設定triggerの対象外なので、影響するdraft月の
共通source再計算入口をDB担当がscope境界に合わせて決める必要がある。

確認したbody MD5：attendance gross trigger
`dd6a3fc3cabc8b5b4985f0e7389c76b8`、detail trigger
`a4286c027860e960735934e4c2089cc6`、gross wrapper
`5931608c50c554eb7fbd75bc9144628e`、worker設定trigger
`e54f70cde281b21c0947b29faba0cde8`。

## 実gross／detailへ通す採用点と最小read権限

計算の修正点は**現在の月次internal grossの手当loop**と**現在のdetail同期の手当集計**
の2箇所。sourceは `20261008200018_paid_leave_wage_contract.sql` の後続最終bodyに
照合する。新attendance配列が明示保存された行のみID＋quantityで会社共通価格を解決し、
旧names branchを同時加算しない。旧rowは従来個人価格branchを保持。両計算が同じ
source resolverと数量policyを使わないとgrossと表示detailが再びずれる。新共通source
のrevisionは既存fingerprintへ含め、会社価格変化を「実績不変だから再計算不要」と
誤判定しない。確定済み／manualを触らない現行早期returnとsnapshot境界を維持する。

employee projectionはpublic read RPC一つで会社idをexplicitに受け、auth.uid＋
その会社memberを確認し、worker表示用id/name/unitだけを返す。価格解決はprivate
計算側だけで行う。PUBLIC／anon EXECUTEはrevokeしauthenticatedだけ個別grant、
rate table SELECT／UPDATE grantや既存admin state権限の拡張は不要という最小案。
既存member units RPCと同じ信頼境界に、曖昧なlimit1会社選択を避けたcompany scopeを
追加する。現在の本番table ACLはpostgres／service_roleのみ、authenticated価格readは
admin state RPCのrole確認下のみであり、その境界を維持する。

sourceAPI実装前に会社3slot永久identity／置換policyを一つ定める必要があるため、
仮想IDを既存name-key mapへクライアント側で付けるshortcutは採用しない。新JSON欄の
従業員readには価格を格納せず、rate row全体serializeもしない。save数量の権限は
既存日報worker access／承認・所有境界に従い、新たな任意company／worker書込権限を
作らない。本書はRPC／DB／UIを一切追加・変更していない。


## 追加report／worker trigger catalog照合

rootのread-only `payroll-daily-trigger-attachments.json` により、前項のreport側
attachment不足を解消した。installed function bodyを読んだ範囲と、今回attachment
だけ読んだ範囲を区別する。実ユーザー保存／削除試験を追加したものではない。

| Table | Actual attachment | quantity採用への意味・確証範囲 |
| --- | --- | --- |
| daily_reports | `report_refresh_payroll AFTER UPDATE` | status列限定ではない。どのreport UPDATEでも関数は呼ばれるが、確認済みbody内 `old.status is distinct from new.status` で給与対象を絞る。署名片側の保存でもtrigger invocationは起き、status不変ならbodyは計算しない。 |
| daily_reports | `report_refresh_invoice AFTER UPDATE OF status` | invoice側はstatus列指定trigger。給与triggerと同じcolumn条件と推測しない。今回invoice function bodyの詳細は未確認。 |
| daily_report_workers | `clear_daily_report_signatures_on_workers AFTER INSERT OR DELETE OR UPDATE` | quantity-only変更もworker UPDATEならこの既存署名clear triggerを通る。関数本体は今回未取得なので、いつどの署名を消すかはDB担当が実bodyで照合する。 |
| daily_report_workers | `reject_direct_report_worker_delete BEFORE DELETE` → `private.reject_direct_attendance_delete()` | 下書保存のworkers削除／再insertにも既存delete guardがかかる。日報変更の権限を広げて迂回せず、保存RPCと実JWTによる通過を試験する。 |
| daily_reports | `clear_daily_report_signatures_on_draft BEFORE UPDATE` | 日報header更新とworker更新は別trigger境界。数量をheaderだけに置くshortcutを採用しない。関数本体による条件は未照合。 |
| daily_reports | `daily_report_shift_identity_guard BEFORE UPDATE OF company_id, report_date, site_id, route_assignment_id` | quantityだけの変更とshift identity変更は別境界。既存所有／shift guardを維持する。 |
| daily_reports | `reject_direct_report_delete BEFORE DELETE` | report削除にも同じ既存delete guardがattached。実ユーザー削除許可の確認は未実施。 |

report_refresh_payrollのattachmentとbody、attendance gross/detailのattachmentとbodyは
定義上確認できた。残る未検証はData API実JWT・guard通過・署名clear関数本体と
新quantity round-trip／給与金額／確定snapshot不変の実行試験、およびcapture後に
DB担当が作業する新scope契約との互換である。権限・sourceAPI・UI・schemaは変更なし。
