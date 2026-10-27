# Build 24 所属切り替え・会社休止の調査と独立候補

基準main: 3b08b17b9666e764a628e77e67b8f0005b668ca5。

## 既存構造（読取調査）

- 本番SKO IDは private.personal_sko_ids。認証のauth userを作り直さずこの対応を維持する。
- public.workersは会社と従業員userを結ぶ。affiliation / partner_company_id / status を持つ。過去勤怠や給与が参照するworker IDを別会社に付け替えてはいけない。
- company_membersは会社権限。画面の種別だけ変更しても旧会社への権限が残るため、実行時にサーバーの現在権限を照合する必要がある。
- partner_companiesは元会社内の既存登録。代表者が使う実companies行と同一とは仮定せず、正規の会社情報・代表者権限の照合を要する。
- 既存 SubcontractorTransferFolder は複数workerの会社データ転送用。今回の本人記録を新会社へ移さない要件には転用しない。

## 実行契約（未実装）

本人の有効セッションと同意、元会社管理者、対象会社と既存協力会社の正規照合、代表者権限をサーバーが検証する。予約日時は日本時間の日付境界で処理し、当日に証拠・権限・全体機能スイッチを再検証する。権限喪失や会社状態変化なら自動実行を止めて要確認にする。

PDF保管完了の正規receiptを前提に、同一request IDの再試行を一度だけ適用する。本人と両会社を一定順でロックし、所属期間と会社権限の履歴を追記する。切替直前から残る認証tokenでも旧権限で書けないようDBが現在の所属/会社状態を毎回検証する。全書込API・RPC・Storageを休止制御で守るため、単独の画面切替だけでは完成しない。

会社休止は旧記録の削除や別会社への移管を伴わない。未処理承認・支払・他の管理者や従業員がいる場合、機械的な会社全体休止は行わず、権限と継続運用を確認する。再開は同じ会社IDと正規代表者確認を使用する。

YESは既存の会社間連携の申請・承認条件を守る。取引先登録を重複させず、書類公開権限を自動付与しない。NOは所属切替だけで、後から正規の連携を実行できる。

## 候補の範囲

transition_plan.mjs は隔離されたオフライン計画部品。証拠refの中身を検証せず、認可・予約・DB変更は一切しない。合成テストは計画の不変条件のみを確認する。実スキーマ、RPC、UI、権限書換、PDF生成、実本人承認、履歴保存、CI・本番・実機は未完成。rootへの事前報告なく共有schema/認証ファイルを編集していない。

## 隔離申請ledger追加（未導入）

`sql/request-ledger.sql.review-only` は私有schema内だけに作成。既存認証helper・元会社管理者・workerとcompanyとpartnerの一致・既存5gateの共有ロック・正規証拠4種を照合し、10分のprepared申請を保存する。planは変更/削除不可、applied化は未実装のため拒否する。同一申請は同じactor/session/planでのみ再利用可能。証拠テーブルへの公開入力APIも実行権もないため、実本人同意/代表確認/PDF receipt発行のadapterが完成するまでは利用できない。

テストの認証helperは合成fixtureの代役。実GoTrue・DB同時操作・実所属切替・時間指定実行・復旧・全APIの会社休止制御は未検証/未実装。prepared申請の取消は履歴を保持するが、適用後の巻戻し処理はない。本番は変更していない。

## Vault本人確認接続（未公開）

`archive-consent.sql.review-only` は本人セッションでのみvault既存 assert_transition_ready を同一transaction内で呼び、会社・worker・切替request・snapshot・完了を照合して本人確認receiptを保存する。管理者が本人の代わりに同意できない。gateと申請行とmanifestを保持し、OFF後は既存receiptがあっても成功としない。実Storageの保存保証はvault側の未完成条件に依存する。

Native専用CIはPostgres17で本番由来session helperと実vault候補SQLを合成テーブルに組み合わせる。既存user/membership切替は実行しない。本人・代表権限の証拠発行、会社間連携RPCへの書込接続は未完成。YESでも相互承認を飛ばす権限は付与しない。

## 代表者確認・既存連携への参照接続

`representative-link-consent.sql.review-only` は既存対象会社ownerと正規の代表権限証拠が揃った申請だけ承認receiptを記録する。会社ownerが存在しない場合の初回代表者検証/登記照合は未接続であり拒否する。会社間連携YESは元会社管理者が既存 private.trade_company_link_requests の同じ会社組・accepted・responded_byありの行をロック照合して参照するだけ。既存リンクを作成/承認せず、権限や取引先を自動作成しない。実connectionの現状態・開始月・取引先重複解消は担当の既存連携adapterで引き続き確認が必要。

Native fixtureに対象会社owner/証拠照合・pending link拒否/accepted link参照を追加。これは実所属適用や会社間連携の自動書込の完成を意味しない。

## Forward適用候補（運用不可）

`apply-forward.sql.review-only` は本人セッションと最新証拠・元会社管理者・対象会社owner・本人vault完了を同一transactionで再照合し、当日の従業員→代表者切替だけを対象にcompany_membersの更新を実行する候補。元workerの会社や過去の勤怠・給与は変更しない。失敗時は権限変更とreceiptを一緒にrollback、再試行は既存receiptを返す。実連携YESと逆方向はまだ拒否。

重要：運用readinessは全false、外部GRANT0。本人/代表者証拠issuer、旧会社へのアクセス境界、在籍workerの扱い、適用後復旧が実装・レビューされるまで必ず拒否する。既存company_members削除はpayroll_access/member_language_preferencesをCASCADE削除するため実データをそのまま適用してはいけない。Native fixtureのtrue変更は試験専用で本番手順ではない。これは本番有効化可能な完成品ではない。
