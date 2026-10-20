# 保険料・社内共通手当: 本番未反映から進む最小工程

基準main `ab9e13fa`（PR #1309統合）。この文書作成では本番へ接続していない。既存隔離成功の再実行、DDL/DML、Auth/RLS/role/providerの変更は0。SQLファイルは**READ ONLY照合案**で、migration・適用コマンドではない。

## 最新の既root観測を優先する

[Issue #273の最新節「2026-10-21 JST・build 6実機指摘の継続」](https://github.com/robin4250/sk-works/issues/273)を読取確認した。同節は「共通手当の6body・activation/publication表は本番に存在し、検証対象と一致」と記録している。**共通手当backend一式が現在も未導入とは断言しない。** 10/17・10/19の未導入記録は過去の観測であり、今回の次工程を過去の不在へ戻さない。

これは既rootのcatalog照合記録を参照したもので、この担当agentが本番を新たに照会・適用したという意味ではない。同節で会社の適用月・本人条件・実額は未読、実給与修復も未実施とされている。6body一致だけで全認可closure・全対象会社のactivation/publication行・本人条件/実額・配布/実機成功を推測しない。以下のcatalog案は未確認差分/鮮度が必要な場合の計画であり、既rootが同時点に確認済みの6body/table存在を無駄に再照会する指示ではない。既保存catalog証拠を先に再利用する。


## 1. いま分ける3状態

| 対象 | sourceで実装済み | 未導入/未確認 | データがなければ進めないこと |
| --- | --- | --- | --- |
| 個別保険料 | 適用月付き本人条件read/save、5保険の明示月額、空欄/0区別、保存後の既存未確定refresh/sync、明細named fields。新sourceのmain統合は実機更新と別 | manual候補はreview-only。4関数のlive状態、本人readerの契約広告、現server/実JWTとUIの接続は今回未照合 | 同一会社/本人/月/statement/revisionを固定。本人負担額・加入/適用資料がない場合は推測登録しない。手入力月額は自動保険計算の欠落履歴を復旧するものではない |
| 共通手当の設定保存 | 既存catalog editor、CAS、pending/receipt照合 | 最新Issueに既rootによる共通6body・activation/publication表の存在/候補一致記録あり。旧未配備記録から前進。6body外の依存全体まで一致済みとは拡大解釈しない | 保存前の旧3枠原値・stable ID/generation・source/versionが必要 |
| 共通手当の給与適用 | bridge/effective source、適用月UI、退勤相当勤怠INSERT/編集UPDATEから実triggerを通す隔離検証、server件数のinline表示 | 共通6body・activation/publication表は既root観測で候補一致。今回会社の適用月/対象行・本人条件/実額・実JWT/実機は未読または未確認 | 対象給与形態・適用開始月・未確定scope、明示hours、旧個別項目・手動調整との整合が必要 |

現行publicationは現在月以降の新しい適用月だけを許可する。「過去月も含む未確定給与全件」の訂正には不足しており、既存拒否を削除して過去月へ広げない。過去月訂正は原本・承認・復旧を伴う別scope。

main ab9の件数表示はinlineだけ。`recalculated_scopes`は計算経路を通ったscope件数であり、全員の保険額が正しいことやblocked解除を保証しない。0と不明を区別し、除外人数/理由を想像で追加しない。

## 2. 先に行うREAD ONLY照合

同ディレクトリの3案を順にレビューする。実行先project/DB/reader identityと非公開出力先を先に固定する。書込可能な既存RPCやpreviewを「SELECTだから安全」と呼ばない。ここではユーザー定義関数を呼ばない。

1. `catalog.sql.review-only`: 既rootの保存catalogを先に照合し、未確認の対象/新たなdriftだけが必要な場合にREAD ONLY transaction内で、必要objects、exact signatures、body/definition hash、OID/owner/ACL/security/search_path、triggers、column/default/RLS/ACLを確認。業務行・Auth行・本文原値は取得しない。欠落関数/表はNULLのまま報告し、不在とRLS無効を混同しない。
2. `insurance_scope.sql.review-only`: catalog通過後、承認されたprivate readerの**bound parameters**で会社/本人/月/statementを1件に限定。条件有無・適用version・mode・五額の型存在・statementのdraft/automatic/final snapshot・明細キー・総額整合の構造だけを返す。氏名・ID・給与額・全JSONは出力しない。これは金額の正誤検証ではない。
3. `common_scope.sql.review-only`: catalog通過後、会社/開始月/給与形態をbound parametersで限定。既存publicationの次境界までの現時点eligible scope数、非draft/手入力/blocked数、activation・version・保存item件数を読む。publishや再計算は行わない。結果は観測時点のplan件数で、後のreceipt件数とは別証拠。

scope案はアダプターから`$1`等をbindするテンプレート。空欄に仮の本人IDを入れたり、Macにそのまま貼って実行させない。実行時は同じ接続で `BEGIN TRANSACTION READ ONLY` と短いtimeoutを設定し、最後はROLLBACKする。missing objectがある状態でscope案を実行せず、catalog段階で停止する。

問い合わせ結果の分類:

- 必要RPC/objectがない → source実装済みでも未導入。保険条件や手当を意味なく保存して修理しない。
- reader対応済み・本人有効条件0件 → 本人資料/適用月の登録不足。仮の保険額や加入flagを生成しない。
- 有効条件あり・明細計算versionが古い → 対象draftの再計算候補を別scopeとして準備。画面reloadはSTABLE読取で再計算ではない。
- 共通保存のみ、activation/publicationなし → 給与適用の未接続。現在単価を全過去draftへ推測適用しない。
- publicationあり、時間項目の数量なし/blocked → 明示hours等の必要入力を解決。人工×8などで補完しない。
- metadata/source/guard不一致 → 現状原本を保護し差をレビュー。古いsourceへ巻戻したりguardを緩めない。

## 3. 適用するなら分ける最小単位

これは適用承認ではなく、後続レビューの対象分割。既root確認済みの導入済み部分を再適用する指示ではない。候補一致の既存objectは保持し、未確認差分や本当に必要な変更だけをこの単位で扱う。既存保護要件を減らさない。

| 単位 | 原本・guard | 変更面と実データへの境界 | 戻す場合の条件 |
| --- | --- | --- | --- |
| M: manual保険codeのみ | `payroll_manual_insurance_20261020.sql.review-only`。validate `4da2bc7e…` / calculate `17ab2de8…` / read `bf7cb912…` / custom-money `5a2ee941…` の**完全MD5は原本を正**とし、metadata・closureも照合 | 既存4関数の限定置換。OID/owner/ACL/security/search_path保持。条件保存・給与行再計算は行わない。common chainを同時適用する必須条件ではない | 4関数の完全before定義/metadataとexact afterが必要。まだmanual条件が一切保存されていないと確認できた範囲のみcode復元を検討。manual行が合法保存済みなら、旧validator/calculatorへの盲目的復元は互換性を壊す |
| C0: 既存identity基盤 | `20261009201229_company_allowance_identity_lifecycle.sql`。既導入なら再適用しない | 旧3枠のrandom stable ID/generation/historyと関連wrappers/triggers。未導入なら独立scope。旧3枠原値を移し替える別マスターは作らない | 新IDや履歴が使われた後のDROP/CASCADEは禁止。ID/原値/参照・旧writer保持まで含む復旧が必要 |
| C1: 共通catalog code/schema | `tool/staged_company_common_allowances.sql.review-only`。既存identity helpers/body/owner/ACL、旧unit reader exact guard | 5表・helpers・wrappers・alias trigger・旧attendance unit読取の限定置換。税保存入口も原本に含むと説明。#1155 rate editor候補は手当保存の必須でなく別scope | 新保存前/後を分ける。items/retired/history/receipts/aliasesが非空なら捨てるschema rollback不可。元unit関数復元だけで全復旧とは扱わない |
| C2: 給与bridge code/schema | `company_common_payroll_bridge_20261020.sql.review-only`。augment `5c51172a…`、unit read `cf298ba4…` と前提catalog | activation表を作るが有効会社0。既存augment/read接続と共通hours APIを原本の範囲で扱う。会社activationは別の業務書込 | helper/metadata/数量・個別条件・既存draft/確定snapshotを保護。新しい数量や給与履歴があれば単純DROP不可 |
| C3: 適用月履歴code/schema | `company_common_payroll_effective_20261020.sql.review-only`。bridge resolver `db2de83c…` / augment `8d5ebc9c…` / common_state `905491b1…` とlock_writer | immutable publication/receipt2表・helpers・2public RPCと3関数置換。**install自体ではactivation/publish/再計算しない** | publication/receiptのUPDATE/DELETEは拒否。合法履歴作成後は履歴を捨てて元helperへ戻さない。未知後続変更も保護 |
| C4: 正規会社のactivation＋初回publication | C0〜C3 exact live after確認、対象会社/給与形態/開始月/version/source/request、正規actor/session、scope/rows before | 初めて実給与を更新する工程。activationだけ先に有効化して履歴欠落期間を作ると次のrefreshでblockedとなり得る。安全な初回cutover/会社lock順/atomic性をレビューする専用手順が必要。現時点でその本番runnerを完成済みとは扱わない | COMMIT不明時に新requestで再実行しない。receiptとexact afterをREAD ONLYで確認。給与行・review/audit/経費snapshot・履歴をcode復元で巻戻したと説明しない |
| M-data: 本人条件保存/対象draft再計算 | 実資料・同一本人/会社/適用月・expected version・必要な元方式/他保険/所得税override保持 | 既存正規saveがその本人の適用月以降の自動draftをrefresh/syncする。条件登録なしで再計算APIだけを実行しても保険料は出ない | 条件history、statement before/afterとrevision、audit/review/final snapshot、下流経費保持。後続合法保存後の古いbefore上書き・revision巻戻し・audit削除は不可 |

単一draft再計算/preview候補は別のAPI権限面でありMまたはC0〜C3のinstallに同梱しない。既存source digestはcommon catalog/activation/publicationの全依存を含むことまで確認されていないため、最新共通手当下書き全件に使える汎用guardとみなさない。採用するなら最新helper/source closure、private full-before、実JWT、同時変更・expense snapshot副作用まで別途照合する。previewはVOLATILEかつlockを取る候補で、このREAD ONLY照合案では呼ばない。

## 4. 必要な原本・backup/restoreを動作ごとに揃える

既存 `company_common_allowance_predeployment_20261017.md` と `docs/security/RECOVERY_REHEARSAL_AND_APPROVAL_20261016.md` の完全保護条件を維持する。以下はscope別に必要な内容を具体化したもの。限定hash/metadataだけを完全backupの代わりにしない。

- **code install前**: 実行artifact/依存のSHA256・既存完全関数定義・OID/owner/ACL/security/config/defaultACL・schema/column/default/RLS・関連trigger/event-trigger/依存・sequenceを非公開保存。既存会社/社員/master/所属/役割・認証provider/既存ログインを変更しない。必要な全DB/role/Storage/Auth/Edge復旧原本と実archiveの隔離復元要件は別途未充足ならHOLD。
- **本人条件save前**: exact会社/本人/starts_onの条件全rowと履歴、適用範囲全自動draftの完全before、revision/reviews/audit/final documents・関連経費snapshot、算出元の勤怠/有給/単価/税/住民税/unit数量を保護。1件の条件saveが複数月を更新するので、1明細だけの保護では不足。
- **共通publish前**: exact会社の設定source/version・旧3枠とstable IDs・extras/retired/history/receipts/aliases、activationと全publication timeline、対象形態・適用期間の全draftと除外済みfinal/manual基準、共通hours/個別条件、review/audit/経費副作用を保護。月額/日額/hours入力不足を区別する。
- **隔離実archive復元**: 元本番へ接続しない新規環境、cron/メール/SMS/通知/外部provider等の外向き副作用を遮断。復元原本のID/会社/role/ACL/owner/旧設定/帳票と新候補の差を確認。既存synthetic成功を実archive成功と読み替えず、成功済みsyntheticを再実行して埋め合わせない。
- **復旧分岐**: 未使用codeだけ、保存後/再計算後、COMMIT不明、後続合法更新ありを分ける。最新afterとsourceを照合するguarded復旧案がない段階では本番変更へ進めない。保存済みimmutable履歴の削除、全行古いbefore戻し、DROP CASCADEを復旧としない。

## 5. 次担当への具体的な順序

1. このsource manifestを照合し、対象作業をMかC0〜C3かデータ修復かに一つずつ固定する。
2. 最新Issueに記録された既rootの6body/table一致と保存原本を先に再利用し、未確認差分または鮮度が必要な対象だけ承認されたREAD ONLY catalog観測で更新する。実値やprivate原本をGit/チャット/CIへ転記しない。
3. 本人保険のexact構造照合と共通適用scopeのplan件数を必要な範囲だけ取得する。データ不足なら実資料と正規入力の準備を進める。
4. 実archive保護・隔離復元・code after/unused restore・正常正規actor/旧writer/役割取消/結果不明receiptの未充足条件をその作業単位で埋める。
5. 具体的なartifact、対象範囲、前後条件、復旧、残unknownをreview可能にしてから、必要な本番適用承認を扱う。この文書自体は承認ではない。
6. code本番配備、実データsave/publish、Release配布、iPhone実額/PDFをそれぞれ別の完了状態として記録する。main統合だけで解消扱いにしない。

## 今回の検証

ファイルと参照・SHA256のoffline照合、SQL案のtransaction/SELECT-only構造・bound scope・禁止呼出なしを確認する。**本番/隔離DBへSQL案を実行していない**。既存PGlite/native成功を重複実行していない。問い合わせ結果、実backup/restore、apply runner、正規actor実接続の完了は新しく主張しない。
