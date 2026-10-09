# 住民税の適用開始月・実給与結合（未適用）

Issue #273の個人別住民税を料率設定と分離したsource実装。CLI migration new生成の`20261009161427_resident_tax_effective_month.sql`。
本番未適用。旧固定値から開始月を推測するseed、既存給与明細のbackfill、料率設定へのコピー、認証/会社権限の変更はない。

## 月額timelineと明示採用

resident_tax_private.state/entriesを会社・従業員単位で保存し、version、legacy/timeline mode、明示cutover_month、各effective_monthと整数amount_yenを持つ。
未登録とlegacy mode、およびtimeline採用前の月はworker_payroll_settings.resident_tax_monthlyを直接参照する。計算済み金額を旧欄へ書き戻さない。
timelineは開始月以上の最新effective_monthを直接選ぶ。0円も有効な値。最初のentryはcutoverと同じ月を必須とし、将来の初回登録で開始前の月を勝手に0円へ切り替えない。
legacy modeへ戻す場合も明示操作・version・確認・旧新mode/cutover/entriesのauditを必須とする。

API:
- `save_worker_resident_tax_schedule(p_company_id,p_worker_id,p_expected_version,p_mode,p_cutover_month,p_entries,p_confirmed)` → `{version,mode,cutover_month,entries,updated_by,updated_at}`。
- `read_worker_resident_tax_schedule(p_company_id,p_worker_id,p_month)` → `{state:nullまたは上記state,resolved,history}`。

日付はYYYY-MM-01。modeはlegacy/timeline。entriesは最大120件、16KiB以下の`[{effective_month,amount_yen}]`。amountは0..2147483647の整数、同月重複・cutoverより前・小数・負値・余分なkeyを拒否する。
legacyならcutover=null/entries=[]。初回expected_version=0。履歴readは最新100件を返し、全旧新stateとactor/timeをDBに保存する。
resolvedはlegacyなら`{mode:"legacy",amount_yen}`、timelineなら`{mode:"timeline",effective_month,amount_yen}`。将来entryやstate版番号は現在月の計算sourceに含めない。

## 既存権限と原子的保存

新schemaの全tableにRLS、raw PUBLIC/anon/authenticated権限なし。
public SECINV wrapper→private empty search_path SECDEFで、既存private.payroll_settings_allowed(cid,wid,'edit'/'view')とaccount_access_allowedをfailclosed照合する。
会社・従業員の現存rowを確認し、company→worker KEY SHARE→専用advisory lock→state lockの順で保存する。
owner/adminに権限を狭めず、既存payroll_access can_edit付与済み一般メンバー等の既存権限を再利用する。既存helperを置換しない。

保存前に既存automatic draft各月のresolvedを取得し、保存後に実額/sourceが変わった月だけ既存refreshとdetail同期を実行する。
将来登録・将来entryだけの変更では開始前/current draftの金額、詳細、updated_at、revision、fingerprint、承認を一切更新しない。新しい未来draftを作成しない。
state/entriesの更新・住民税audit・実給与refreshは同一transaction。auditまたは給与計算/給与auditが失敗すれば全体をrollbackする。
現在state/entriesは会社/従業員削除にcascade、履歴はlogical UUID attributionで保持する。保存期間TTLを新設しない。

## 実計算への直接結合

既存`20261008200018_paid_leave_wage_contract.sql`のrefresh_automatic_payroll_internal/sync_payroll_attendance_detailと`20261008045401_preserve_payroll_named_financial_details.sql`のapply_payroll_custom_moneyが旧resident_tax_monthlyを直読していた。
新migrationは3関数のfull definitionsを明示し、それぞれ同じresident resolverを呼ぶ。custom normalizationだけが旧額へ戻してしまう経路も変更する。
calc fingerprintはtimeline期間だけ旧resident_tax_monthlyを除外して選択済みmode/effective_month/amountを加え、未来予定やtimeline version全体で現在月reviewを無効化しない。
実額または計算source変更時は既存計算のrevision増加・approved_ids reset・automatic_recalculation auditを利用する。manual/非draft/finalizedは既存除外条件を保つ。
給与条件が未登録でも、timeline額をcalcとnormalizationで一致させ、毎回revisionが増える不整合を避ける。これは給与条件や給与単価を推測するものではない。

既存3関数のprosrc MD5、SECDEF、empty search_pathのexact prerequisite guardを設ける。元sourceが異なる場合は新schemaを作る前に停止する。未知関数へpg_get_functiondef文字列置換を行わない。
レビューした3bodyのMD5はreadonly live catalogとも一致した。MD5はsource identity照合であり、本番data backupや機能の正しさの証明ではない。

## 実行確認と残り

PGlite 0.3.14に、既存paid_leave_wage用の正確な原典migrations、live_linkage snapshotと実attendance/settings/paid_leave/給与normalization triggersを組み、新migrationを実行した。
synthetic access fixtureは既存会社membership・feature/payroll_access・worker所属・account guardに対応する主要条件を再現する。全professional inviteや本番JWT/署名状態の結合証明ではない。

実SQLで確認:
- 未知calculator sourceをguardが拒否し新schemaを作らない。
- 旧固定12000円・月給300000円→net288000円を維持。将来初回登録では現在draft全field完全一致、未来draft生成なし。
- current cutover15000円でnet285000円、開始前の月は旧12000円。0円でnet300000円。旧fixed欄12000円のまま。
- 将来entryだけの変更はcurrent draft全field完全一致。実source変更でreview reset/revision/fingerprint変化。
- legacy→timelineのmode/cutover/entriesと旧新値actor/timeをaudit保存。
- can_edit普通メンバーのsave、can_viewのみのread、viewのみsave拒否、他社/anon/account停止/raw権限/version/不正月額拒否。
- manual/finalized明細の全field完全一致。
- 住民税audit失敗・給与refresh audit失敗がstate/entries/historyおよび明細全fieldをrollback。
- wage settings未登録でもtimeline deductionとnormalizeが一致し、同一refreshでrevisionが増えない。

CIはpin/ignore-scriptsのruntimeで同fixtureを再実行する。
実Postgres並列セッション、全本番schema/permissions/JWT、既存会社/従業員削除全経路、バックアップ、UI保存・適用popup・最終明細接続は未検証。本番migrationは未適用。
CLI local DB/advisorsはDocker/Podmanと稼働local DBがないため利用できず、本番へ切り替えて試験していない。

## UI採用の確認

`public.resident_tax_schedule_contract_version()` はauthenticatedだけが実行できる読み取り専用RPCで整数`1`を返す。これに成功した場合だけ新しい住民税schedule UIを採用する。RPC未導入と確認できた場合は既存固定住民税入力・一般保存を維持する。ネットワーク障害・権限等の別エラーは未導入とみなさず、確認不能として扱う。このgateはtimeline設定済み・公式検証済み・本番適用済みという意味ではない。
