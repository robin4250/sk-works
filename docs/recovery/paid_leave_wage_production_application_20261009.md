# 有給給与契約の本番適用記録（2026-10-09）

有給給与契約を本番へ適用した。既存明細の再計算、iPhoneでの実操作確認、TestFlight公開とは別の記録である。登録データ、会社・社員の識別子、個人の金額は掲載しない。

## 適用したソースと台帳

- 基準main：`a086828bb46819d74ca1bf9bd245e8f94a90dbdf`。
- 正確な適用ソース：`supabase/migrations/20261008200018_paid_leave_wage_contract.sql`。
- ソースSHA256：`97ecb83ccc405d1d006423e558fbb2de91039ef86f4ebec7afc950df4d8cc62a`。
- 本番migration version：`20261009100557`。
- 本番migration name：`paid_leave_wage_contract`。

本番台帳のversionとリポジトリのファイル時刻は異なる。台帳を揃えるための再適用や書換えは行っていない。

## 保護と適用方法

適用前に対象限定の復旧用snapshotを保護された場所へ保存した。checksumは `53eb82630c9189441225a77d19dbea9860e8991a24e83408727759ace1bdf93b`。復旧用の実関数定義・ACL・関連metadata・対象計算入力・比較用明細を含む。全DB、Auth、Storageのバックアップや復元演習ではない。

対象15表のSHAREロックを取得した同一トランザクションで、保存したcapture JSONとの同一性を検査した。比較から除いたのは取得時刻とtransaction read-only表示のみ。guard成功後に上記migrationをそのまま適用し、COMMIT成功を確認した。登録行のバックフィル、手動refresh・scheduler実行、新cron登録は行っていない。

## 適用後の確認

- captureの差分は関数とmigration台帳のみ。既存給与明細2件の全行、全計算入力、表ACL・RLS、トリガー、cronは不変。
- 保存37関数の比較で、変更signatureは置換5関数と新helper・capabilityの7件だけ。更新・新設7関数の`prosrc`が適用ソースと完全一致。
- 関連private 6関数はanon／authenticatedからの直接実行を拒否。
- capabilityはSECURITY INVOKER、authenticated実行許可、anon実行拒否。authenticated roleで実SELECTし、返却値1を確認。
- 合成JSONだけを使ったhelper確認で、日給、時給×8時間、手動0円、月給の内訳単価の4ケースが成功。
- 既存の角印snapshot保持契約、manual／finalized保護、既存トリガー・cronを維持。

## 運用上の状態と未完了

この契約に会社別OFF gateはない。capabilityは適用直後から1であり、通常の給与設定・出勤・有給変更や既存の当月schedulerで新関数が使用される。「本番適用済みだがrollout OFF」とは扱わない。

今回、旧draftを手動で再計算していない。既存明細に保存された旧金額・警告がすべて新契約へ更新されたとは確認していない。最新iPhone導入、有給入力・給与計算・PDFの実操作確認、TestFlight公開は未確認／未実施である。

## 復旧の境界

異常時のDDL復旧は、保存した実定義・所有者・ACLを使って置換5関数だけを戻し、新capabilityからhelperの順で撤去する。角印関数・他の依存関数・既存トリガー・cronを古いmigrationで巻き戻さない。

DDL復旧は適用後のdraft金額を元に戻す操作ではない。正当な勤務・承認変更を保護し、対象明細の差分を確認したうえで必要なデータ復旧を別途判断する。manual／finalizedや過去明細の一括上書きは行わない。

関連資料：[適用・復旧条件](paid_leave_wage_rollout_20261009.md)、[適用前の読み取り確認](paid_leave_wage_live_preflight_20261009.md)。後者の未適用記載は過去時点の観測であり、現在の適用状態は本記録を参照する。
