# 家族手当・個別住民税の保存/給与接続契約（未実装）

調査基準: main `ae80103101f303291cc84c6094b02df5bcf3b15d`（PR842 merge）。既存sourceのread-only調査。DB、Auth、RLS、UI、migrationは変更していない。純粋モデルの存在や本契約は給与への自動反映が完成したことを意味しない。

## 既存sourceと再利用するもの

| 内容 | 既存source | 現在の意味/不足 |
| --- | --- | --- |
| 個別設定保存 | `IndividualPayrollSettingsRepository.saveSetting` | worker_payroll_settingsへ直接upsert（worker_id conflict）。月額/配列等を保存。新条件のversionや履歴保存APIではない |
| 家族の登録情報 | `worker_family_members` | company_id/worker_id/name/relation/birth_date/is_dependentとactor/time。家族手当専用資格や有効期間なし |
| 家族画面モデル | `PersonnelFamilyMember` | isDependentは登録された扶養flag。ageOnは通常誕生日年齢。家族手当/所得税/保険制度の資格判定を保証しない |
| 登録済み家族取得 | `private.worker_personnel_payload` / `private.employee_personnel_rows` | 適用済みworker_family_membersを参照。自由記述family_compositionは人数sourceにしない |
| 家族保存 | `public.save_worker_personnel_profile` → `private.apply_worker_personnel_payload` | 初回/owner/adminは直接適用経路、その他は承認request。適用済みtableと未承認requestを混ぜない |
| 家族手当の現行金額 | family_monthly + custom_earnings | 現在は別支給として合算。登録家族人数とは連動しない |
| 住民税の現行金額 | resident_tax_monthly | 開始年月なしの個別固定月額。会社料率ではないが毎回同じ値を計算器が参照 |
| 最新自動計算/内訳 | `20261008200018_paid_leave_wage_contract.sql` | family_monthly/住民税を固定金額として直接読み、automatic draftのみ更新 |
| 追加金額normalization | `20261008045401_preserve_payroll_named_financial_details.sql` | family detailと住民税を含む控除合計を再構成。新計算器だけ変えても旧固定額に戻される危険あり |

家族schema/RLSの導入sourceは `20261002013355_add_worker_family_social_insurance_details.sql`。最新適用payloadは `20261008004843_employee_registered_identity.sql`。家族行は保存時に同company/worker全件DELETE→INSERTされ、送信されたidを再利用していない。`EditableFamilyMember.toValue`もidを保持しない。したがって現行family IDを永続的な人物identityや給与snapshotの唯一の変更versionとして使わない。再挿入だけで人数が変わらない場合もある。

## 家族手当の接続

1. 家族手当を標準の一項目として識別し、共通手当masterのstable IDを参照する。名称だけで既存custom項目を自動吸収しない。同名家族手当の既存直接入力は別の明示移行対象として利用者に確認する。
2. 資格adapterはcompany/workerと計算対象期間を入力に、適用済み登録家族情報から対象人数を返す。未承認変更request・招待中の仮情報を数えない。現行is_dependentを自動的な家族手当資格や税扶養条件とみなさない。配偶者/子/扶養/年齢/有効期間・基準日について会社の対象規則が確定するまでadapterを有効化しない。
3. 個別条件は `count_mode=automatic|manual`、nullable manual_count、単価/計算basis、適用期間、条件versionを保存する提案。manual 0は有効値。`automatic`ではadapter人数を使い、manualでは家族登録更新があっても手動人数を保持する。自動に戻す操作はmode=automatic / manual_count=nullを保存し、最新適用済み情報で再計算する。auto結果をmanual欄へコピーしてmodeを曖昧にしない。
4. 対象人数0なら算出支給0。設定画面では0と根拠を確認でき、明細では0円項目を非表示にする。設定/監査履歴を削除しない。adapter取得失敗/資格不明を対象人数0へ黙って変換せず、未確認または計算blockedとして扱う。
5. 既存family_monthlyとcustom_earningsの家族手当を残したまま新自動家族手当を加算しない。`20261006162510_payroll_flexible_earnings_deductions_payment_day.sql` は旧family_monthlyをcustomへ移した過去のseedを持つが、現在は利用者が両方を登録できる。名前/金額だけではどちらが重複か判断できない。明示移行で採用先と旧項目の扱いを確定し、before/after履歴を保存する。
6. 給与snapshotは採用人数、auto/manual、資格規則version/基準日、単価、結果、家族sourceの必要最小限のversion/fingerprintを記録。家族全氏名/生年月日を給与明細や日報へ展開しない。

DBで不足: 家族手当条件のmode/manual_count/basis/単価/期間/version、会社側資格rule、条件更新のactor/time/before-after履歴、適用済み家族変更→自動draft再計算の連携。worker_family_membersへの直接書込権限を広げて解決しない。適用payloadのtransaction中で子行DELETE後の一時0人数を計算せず、全家族を適用した後に一度だけ対象給与をrefreshする設計が必要。

## 個別住民税の接続

1. company/workerをscopeとし、開始年月+非負円整数月額を登録。同開始月重複を拒否し、変更は明示amendとexpectedVersion、認証済actor、server time、before/after監査を要求。未来版は事前登録できる。
2. 対象給与月以下で最新開始月の版だけ採用。対象月をperiod_start等のどの月とするか、会社締め期間も含めて明示する。システム現在月や支給日だけを使って過去draftへ最新額を適用しない。開始前/未登録と明示0円登録を区別する。制度の税率/年税額/分割を推測せず通知書等を利用者が確認して手入力する。
3. DBは既存worker_payroll_settingsに一つのtimelineを持つか専用の個別effective tableを設けるかをrootのschema laneで決定。どちらでもcompany/worker/開始月の唯一性とworkerが同社に属する整合を確保する。既存resident_tax_monthlyは互換経路として保持し、開始年月不明の値を現在月から始まるhistoryへ勝手に変換しない。
4. 適用結果をresident_tax_monthlyへコピーする方式にはしない。最新計算器、custom_money normalization、内訳syncが同一の採用版/月額を参照する。互換fixedと新timelineの二重控除を防ぐ明示modeが必要。
5. 保存時に変更の影響を受けるautomatic draftだけを再計算。未来版登録だけで開始前の給与の金額を変えない。版選択/月額/条件versionが変わればfingerprintとrevisionを変更し、以前の確認revisionを再確認対象にする。

DBで不足: 開始月timelineまたはeffective rows、履歴/versionとatomic保存RPC、legacy/timeline切替、月選択resolver、影響月だけrefreshする連携。純粋モデル `ResidentTaxSchedule` はPR843の候補で、認証/実DB権限・毎月自動反映は提供しない。

## 明細表示と確定境界

PDFは `_mergeMoneyEntries` が1円未満を除外する一方、configured name/amountとlegacy detail aliasを金額一致時だけ重複除外する。名称を同じにするだけで重複支給を防げるわけではない。新standard IDの明細sourceを定め、snapshot条件metadataはnonmoneyとして扱い、人数やversionを円項目に見せない。画面明細にも同じ0円抑制を適用し、合計は採用resultと一致させる。

既存計算器/内訳/normalizationのautomatic=trueかつworkflow_state=draft条件を保持する。manualとfinalizedは家族情報/住民税条件の更新対象から除外。確定時に採用版・条件・結果を保存してから状態を原子的に遷移し、後の条件変更でも保存結果を読む。レビュー確認はrevision記録であり、現在の `finalize_payroll_review` の名称だけではfinalized遷移を意味しない。詳細は `payroll_snapshot_adoption_contract.md`。既存確定値を新adapterから逆算して埋め直さない。

## 接続前の必要な検証

- 最新installed schema/RPC/trigger/grantsをread-only照合。worker/companyscope・旧client保存・expectedVersion conflict・サーバactor/timeを検証。
- 適用済み家族0/複数、未承認変更、manual 0、manual維持、自動reset、取得失敗、家族全件置換途中の0誤計算なし。
- 住民税開始前/exact開始月/次版/年越し/未来登録、同月重複、明示0、旧fixed互換、会社跨ぎ、支給日と対象月の区別。
- 一度の計算で旧家族/新家族および旧住民税/新住民税を二重加減算しない。明細0抑制と支給/控除/netの合計一致。
- 自動draft変更時だけrevision/確認を更新。manual/finalizedの行全体とその明細の再計算監査が保持される。

この調査では本番個人データの取得、権限変更、migration適用、既存画面変更を行っていない。
