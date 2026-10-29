# 社員coreの導入レビュー案（実適用・有効化なし）

更新基準は実取得したmain `386ca8a3a66d4b95a8c4d8ba3c417a770242dde5`、tree `788c9822631397df181f0b71732ed9eab8ae167e`（PR1598統合後）。この文書だけを同mainから更新したもので、古いworktreeの製品ファイルは上書きしていない。main統合はソースの状態であり、本番DB・Edge・公開アプリの導入状態ではない。本稿は候補の具体的な導入・復旧レビュー用であり、SQL実行手順への承認ではない。本稿の作成で本番DML/DDL/RLS/GRANT、Edge deploy、flag ON、登録済み口座・書類・原本・署名の変更は一切行わない。個別書類免除は導入済みのOFFを維持する。

## 保存済み候補と確認済み証拠

|対象|固定source / 検証|意味と限界|
|---|---|---|
|DOB 3 helpers|PR1578 `206445a8c75378874db6f0176b6b1f14cd340f99`、native job123461097244 34 checks、client job123461096838 38 tests、当該head10/10成功|nullable date/payload/apply/scoped view。nativeは合成roles/claimsであり実GoTrueではない。退職修正・銀行hook等を含む最終leafはPR1592でsource blob/mode照合済み。DOB実GoTrue・4関数原子組成は別途未証明|
|DOB fourth public save|PR1589 `d19fa8fc57f0bfd88f65f92ac083091a34e99ef6`、tree `ab3ebfc921976fb41296ff449a780ee17940c574`、native job123580201092 30 checks、5/5成功|canonical no-op、marker除外、omission、pending proposal保持。3helperとは一体導入が必要。実GoTrue未証明|
|本人銀行登録|PR1575 `493def6866e7d0bd0a9cb1db9a25b50b668eb3f1`|既本人APIの正規会社/社員照合を利用。本人フォームを他社員に流用しない|
|他社員銀行初回登録|PR1581 `a3a70342451d1ec7df51e23e5f9986f0e9fe4c7a`、tree `f422af33c842a40b679485d655370d11ea429156`、native job123461781006、実GoTrue/PostgREST job123461781303 73 checks、client job123461781340 19 tests、21/21成功|既proof issuer/consumer＋primary-password broker。selected会社/社員/input digest/liveSIDを束縛、insert-only、既口座上書きなし。source/fixture成功は本番導入ではない|
|本人書類編集入口|PR1586 `877c7db6551fee35725296c39ca9ec939c392abc`、13/13成功|既変更申請画面へ接続。backend未導入時は利用不可、旧直接更新fallbackなし|
|書類変更backend successor|PR1590 `aec9bda3b6d82e6435e37bafb136667b748b8d4a`、tree `ad3b3615aeb47cb3dd50567a4cbfba4df9197ee9`、実GoTrue/PostgREST/PG17 job123581007619 62 checks成功|OFF/復旧、現在scope、旧SID失効→新SID明示再開、実Lock2本を観測した同時承認single apply/history等。当該head一般validate job123581168550も成功、全9/9成功|

|銀行preapply capsule|[PR1594](https://github.com/robin4250/sk-works/pull/1594) `d24c8166d37ef762439c84063147127b3cad8464`、native job123596715334 44 checks、8/8成功|8既関数の定義だけでなくowner/ACL/config等と実bank triggerを前後照合。単一transaction・late failure rollback・非空既存原本保持・未使用復旧を新PG17 fixtureで確認|
|銀行→書類guard組合せ|[PR1596](https://github.com/robin4250/sk-works/pull/1596) `8316facb4908f96b7148214d8ff31cbd8bdb09d2`、native job123600849198 35 checks、9/9成功|同一PG17 fixtureで実同期triggerのself両OFF、manager/docOFF、manager/docON申請中を確認。画像/notes/期限保持、古い申請承認40001、context/ticket空。合成claimsであり組合せ実GoTrueではない|
|社員core統合|[PR1592](https://github.com/robin4250/sk-works/pull/1592) `3b2d8b21607ba1c4c0e9fc4e6e4f79551a73d506` 48/48成功、validate123591717016・iOS123591714868|main `80e2650d984abbd7a9b0c6f4fc4787374cf137ad`へnormal merge、同tree `65041c278f0fca8f0442ddf113211ed871305014`。post-main 10/10成功|
|銀行hook/capsule/組合せ統合|[PR1598](https://github.com/robin4250/sk-works/pull/1598) `c280ea23fcb4a381d037c8c3d6bcb6740036f801` 34/34成功、validate123610883763|main386へnormal merge、tested tree `788c9822631397df181f0b71732ed9eab8ae167e`一致、33 source pathsの最終blob/mode一致・追加変更0。post-mainは別監視|

CI根拠は各固定headのGitHub check-runと統合PRの照合結果を確認したもの。今回の文書更新では既成功native/実GoTrueを再実行しない。main386のpostmerge CIは観測時14件中13件成功、validate123623334663実行中であり、PR1598の34/34と混同しない。銀行＋書類の限定Native組合せ成功を、DOBを含む全moduleの原子適用・全本番schema・組合せ実GoTrue・実機の証明へ読み替えない。

## 導入前に固定するcatalogと保存証拠

実施担当は、承認対象となる正確なリポジトリtree、全候補/復旧SQL、対応Edge artifactを固定し、変更前の原定義と属性を保護された保存先に保存する。公開repo・ログへ社員値、口座番号、名義、JWT、鍵、パスワードを入れない。ここでは個別本番行を追加取得しない。

1. 対象関数の`pg_get_functiondef`と`prosrc` hash、owner、ACL（NULLと明示ACLの差を含む）、SECURITY DEFINER、search_path、volatility、strict/leakproof/parallel/kind、戻り型を照合する。DB全体のdefault privileges、実行role、PostgREST公開schemaも固定する。
2. DOBは`private.worker_personnel_payload(uuid)`、`private.apply_worker_personnel_payload(uuid,jsonb,uuid)`、`private.employee_personnel_view(uuid)`、`public.save_worker_personnel_profile(uuid,jsonb)`の4本。正規save/approvalが参照する`can_edit_worker_personnel`等、承認件数設定・承認関数・pending/request保持とworker/profile制約も照合する。DOB列が既に存在する場合は無条件再実行しない。
3. 銀行はinstaller先頭の8既関数を照合する。既private proof issuer/consumer、scope/required、public issuer wrapper、live-session helper、`sync_bank_document_status`、`has_company_feature`を含む。既worker_private_bank_accountsのCHECK/PK/RLS/ACL、self-only trigger、正規payroll permission、reauth rollout/ledgerとそのFK/制約も保存する。
4. 書類はlive-session/account/people helpers、statuses/history/Storage objects/requirements/member permissionsの列・RLS・ACL・制約、audit/normalize/baseline/retention triggerと関数、FK actionsを照合する。既company/worker/requirement→status CASCADE、auth/template→SET NULLを維持する。新request/event/ticketが既に存在すれば再導入せず利用履歴を調べる。
5. 個別書類免除settings OFF、既function属性、既免除/履歴の保存照合を引き継ぐ。既保存バックアップと原本照合履歴（root報告の最新版69、旧保存版55を含む）を置換せず、後続の導入前後catalog/照合と未使用復旧候補を追加保存する。バックアップ保存完了と隔離復元成功は区別する。過去原本・署名・給与・口座・書類履歴の保全を個別に確認し、実データ値を公開ログへ出さない。

**属性gateの解消済み範囲と残条件**：凍結済みraw銀行installer/restore自体は引き続き`pg_get_functiondef` MD5のみを検査する。新capsuleはその原文SHAを固定して内包し、8関数の定義・owner・ACL・config・SECURITY DEFINER・volatility・strict/leakproof/parallel/kind・戻り型、実`sync_bank_document_status` triggerの定義/enabledを同一transactionの前後で厳密比較する。owner/ACL等のdrift拒否は44新checksで確認済みであり、未実装とは扱わない。導入候補はraw installer単独ではなく、このcapsuleとの組合せで評価する。保存catalogは2026-10-29のreadonly観測であり、実適用直前のfresh照合・全現在schema/依存物・保護された原定義checkpoint・隔離復元はまだ別条件である。協調advisory lockは非協調の管理者DDLまで防ぐ保証ではない。DOBと書類の属性guardも、全本番schemaの証明ではない。

## 候補間の依存と導入順（実行用SQLではない）

### 1. DOB 4関数を一つのtransactionで導入する候補を確定

`employee_personnel_birth_date.sql.review-only`の3helper＋nullable列と、`personnel_birthday_noop.sql.review-only`のfourth public saveを、一つのレビュー済みtransactionとして組成する。前者だけをcommitして新read contractを公開しない。両sourceにはそれぞれBEGIN/COMMITがあるため、そのまま連結して「single transaction」と扱うことは禁止。正確なsource/hash/anchorを検査した組成物で最外側transactionだけを残す、または同等の明示的な原子導入候補を別途レビューする。本稿ではその組成SQLを生成・適用していない。

3helperのpayload hashをfourthのdependency guardが要求する。導入後は4関数の内容・属性、新列nullable/型、marker/no-op/omission/approvalの契約を確認する。既DOBがある環境や同名関数driftでは中断し、上書き・列再作成・データ初期化をしない。DOBには新たなdefault-OFF gateがないため、このtransactionの公開自体を別の導入判断として扱う。

### 2. 他社員銀行moduleをOFFで導入する候補を確定

`docs/candidates/employee_bank_preapply_capsule_20261029/install.sql.review-only`を導入候補としてレビューする。これは凍結`tool/staged/employee_bank_initial_registration.sql.review-only`をexact SHAで内包する単一transactionであり、raw sourceを先に適用してからcapsuleを適用する手順ではない。8関数/実triggerの前後属性gateを通す。moduleは新private gateがfalseで、contextのapp/service権限0を確認する。既口座/RLS/CHECK/self branch、private proof issuer/consumer/session helperは維持する。提案された新RPC GRANTは実適用承認の対象であり、ソース統合の承認と混同しない。

matching `reauthenticate-operation/handler.mjs` artifactの`employee.bank.initial` operation、厳密target、genuine password/temp-session cleanup、既collector等の動作保持を確認する。DB module OFFとEdge deploymentは別段階。Edgeだけ、SQLだけ、clientだけの状態でmanager登録を成功扱いしない。flag ONは本稿の範囲外で、後日の個別判断とする。

### 3. 書類変更moduleをOFFで導入する候補を確定

`worker_document_change_session_20261029/install.sql.review-only`はhistorical20261019を直接適用する代わりのsuccessorである。新RPC/dispatcher、request/event/ticket、rollout false、app/service direct access0、catalog sealを確認する。OFFは既status操作に介入しない。ONでもactive申請対象のcontent UPDATEだけをticketで保護し、既status/original-only同期・INSERT・DELETE・無申請rowは元RLS/triggerへ委譲する。旧経路全ての保存内容変更を一般禁止する候補ではない。

新SIDはfresh capabilityと明示commandで再開でき、作成SIDは書き換えない。別社員への変更には現在権限、承認には別actorを必要とする。保存済み添付の並べ替え/一覧からの除外は申請可能でも、新写真upload/差替えは未実装のままにする。

### 4. 組合せ確認と照合

関数名ベースでは、DOBが変更する4本と銀行が変更するscope/required/public issuer/sync-bank、書類が追加するmodule関数は重複しない。銀行と書類が共用するlive-session/people/account helperはどちらの候補も本体を変更しないため、source上の直接hash衝突は確認していない。PR1596は銀行capsule＋書類moduleを同一の合成PG17 DBへ導入してこの限定組合せを検証した。DOBを含む全moduleの原子導入や現在本番への適合まで検証したものではない。

実在する接点は、銀行`sync_bank_document_status`が書類statusesを更新し、新書類guardが同じrowに掛かる点である。既bank foundationは`baseline-functions.sql`末尾に実triggerを含む。PR1596の35新Native checksは、その原trigger・凍結module SQLを変更せず、self登録の両OFF、manager登録の書類OFF、書類ONかつactive pending申請中のmanager登録を組成した。statusはsubmitted/original未確認へ同期し、画像・notes・期限は保持、bank context/document ticketは空。同期で元snapshotが変わった申請の承認は40001となり、pending申請・登録済み口座を保持した。この限定cross-module接点は成功済みであり、未試験とは扱わない。

まだ必要なのは、DOB4関数の単一transaction組成と失敗rollback、DOBの正規canonical save/approvalの実GoTrue、全moduleをOFFで導入→未使用復旧する場合の原本/関数/権限照合、現在本番schemaを再現したバックアップ隔離復元である。銀行・書類個別の73/62実GoTrueと、合成claimsによる限定組合せ35 checksを足し合わせて、この未証明範囲が解消したとは扱わない。既成功suite一式の反復では置き換えられない。

各moduleを導入前と比較し、許可した関数/列/新module以外の変更0、既データ/原本/署名/履歴の保持、個別書類免除OFFを確認する。タイムアウト・結果不明時はblind retryや全復旧をせず、catalogとimmutable request receipt/履歴から確定する。

## 未使用復旧の順と停止条件

|順序|候補|必要条件・保全|
|---|---|---|
|1|書類 `restore-unused.sql.review-only`|OFF、request/ticket/event全0、installed/prerequisite function/owner/ACL/config/trigger seal一致。利用1件でも拒否、履歴を消さずforward recoveryへ。DROP CASCADEを使わない|
|2|銀行 `docs/candidates/employee_bank_preapply_capsule_20261029/restore-unused.sql.review-only`|凍結raw restoreを内包し、8関数/実trigger属性を前後照合。gate OFF、context空、`employee.bank.initial` proof履歴0が必要。44新checksで未使用復旧/late failure原子rollback確認済み。proof発行だけでも未使用復旧不可。既口座・給与・文書・proof履歴を削除しない|
|3|DOB `personnel_birthday_noop_restore_unused.sql.review-only`|fourth関数candidate body/attrs一致後、original public saveへ戻す候補。birthday列/値/proposal/承認を保持|
|4|DOB `employee_personnel_birth_date_restore_unused.sql.review-only`|3helper candidate body/attrs一致後に復旧候補。列/値をdrop/clearせず保持。fourth復旧より先に実施しない|

DOBの`unused`は保存された未実行復旧候補の名称であり、DB利用0を機械判定するgateではない（担当ownerにも確認）。保存済DOB・pending proposal・承認・client契約がある場合の無条件利用を許可しない。利用停止、利用証拠/影響、元原定義との意味の整合をレビューし、利用後のforward recoveryは別途準備する。銀行capsule単独のtransaction・未使用復旧・late failure rollbackは44 checksで成功済み。一方、DOBまたは全moduleの復旧SQLを一括連結しただけで原子的/安全とは扱わない。それらには各既BEGIN/COMMIT、dependency、timeout、使用有無を明示した組成とバックアップ隔離復元が別途必要である。

## 残段階と引継ぎ

成功済みは、core1592全48、main80 postmerge全10、統合1598全34、capsule44新checks、銀行→書類限定組合せ35新checksとそのmain386へのソース統合である。main386 postmerge CIの残りは別監視。未完了は、DOB4関数の原子組成/失敗rollbackと正規canonical save/approvalの実GoTrue、全moduleの導入/復旧組合せと現在catalog/原定義checkpoint・バックアップ隔離復元、個別の導入判断・SQL/GRANT/Edge deployment、OFF照合後の個別有効化判断、公開/TestFlight配送、iPhone実機での会社/本人scope・セッション切替・申請/承認の確認である。これらをソース修正やCI成功と同じ完了段階にしない。

新写真差替えは別scopeで未実装。元画像の直接置換、legacy直接saveへのfallback、原本/承認履歴の削除、Auth/RLS/本人会社保護の緩和で代用しない。既個別書類免除はOFFのまま維持する。

## 更新基準main386から再採取したファイルSHA-256

|ファイル|SHA-256|
|---|---|
|`tool/staged/employee_personnel_birth_date.sql.review-only`|`47005bf6973ad86c99af8ecad60f4576596e3c8ee547b1fb01baab78961a6cb5`|
|`tool/staged/personnel_birthday_noop.sql.review-only`|`c4ae672ce99c6a6dc6e3eca1d892345995ed4eea7c72779a11ed3772b383bca3`|
|`tool/staged/employee_personnel_birth_date_restore_unused.sql.review-only`|`2db257e10ba1017c54b957aed16c217580f8ede1c06ff0173b6538c718a1d0e5`|
|`tool/staged/personnel_birthday_noop_restore_unused.sql.review-only`|`47f4042baaba85c7bb2dff20d998fec4ccd9df808c0ac9a65992b0e112cb7ff3`|
|`tool/staged/employee_bank_initial_registration.sql.review-only`|`af83bc3305e24e4db1fb0b4374c69d8df44c3215f358a755674371b228f9105a`|
|`tool/staged/employee_bank_initial_registration.restore-unused.sql.review-only`|`3e963756ab0fe84ceda7674068d762288fb37f11538e61e708aa9ffd1f9fd4d5`|
|`docs/candidates/worker_document_change_session_20261029/install.sql.review-only`|`1f078c9a60e8c19163e7656a5067dec8ae9e20e0703cbd06073069c9e6f830ca`|
|`docs/candidates/worker_document_change_session_20261029/restore-unused.sql.review-only`|`22a5b160761a6e631858fd29d81263367ffe1bad7eed21be7446a8d055bc4e82`|
|`supabase/functions/reauthenticate-operation/handler.mjs`|`1ae77ae635cb748bed4ef5962ad7cec6b2c20cc96d24ef50a89fe430c434e9d6`|
|`docs/candidates/employee_bank_preapply_capsule_20261029/install.sql.review-only`|`9d9ffb159ca10b66ece52c20279dedba73e86a14390bfcc64cb364f6eafeb930`|
|`docs/candidates/employee_bank_preapply_capsule_20261029/restore-unused.sql.review-only`|`4e1ab31722b278147339841aa4b904b95d12c297e1b39b1824fa1c4e337d799b`|

上記はsource fingerprintであり本番catalog fingerprintではない。本番差分があればsource hashを都合よく更新して通さず、原定義・依存・復旧を再レビューする。
