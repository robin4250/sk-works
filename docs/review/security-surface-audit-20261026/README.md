# 残るStorage・RPC・LINE境界の再照合（2026-10-26）

読み取り専用のsource/ACL/catalog監査。実データ・認証トークン・署名・給与・管理者IDを取得/変更していない。mainは保険料対応版 `ff591eef650f2354dc52e16bca981a45808fea3e` に固定し、当ディレクトリの資料は未統合の監査記録とする。本番DDL/DML・機能有効化・実送信は0。

## 新たに確認した範囲

- 本番のauthenticatedにEXECUTE可能なpublic SECURITY DEFINERは197件。朝の保存snapshotと全197件のbody MD5が一致。これは全197 APIの権限試験完了を意味しない。
- 公開RPCの調査母数を197だけにしない。extension-owned関数を除いたauthenticated-callable SECURITY INVOKERも251件、合わせて448件を棚卸しした。invoker wrapperから非公開SECURITY DEFINERを呼ぶ経路があり、R30の公開moderation queueがその例である。448件の実負試験完了を意味しない。
- Storageは16 bucketすべてprivate、98 policyは保存snapshotと全定義一致。12 helperの現行source/owner/ACL/configを追加取得した。`bucket-read-matrix.json` は各bucketの読取policy対応表で、HTTP試験の完了表ではない。
- PR #1437のlive-session候補は `worker-documents` のみにRESTRICTIVE SELECTを追加する。他15 bucketのセッション失効・実HTTP・署名URL/キャッシュの失効までは閉じない。private bucketであることだけで正規/不正アクセスの区別を実証したとしない。
- Data APIのauthenticator pre-requestは `private.check_account_access` が設定済み。現sourceは削除制限とREAD COMMITTED/共有barrierを確認する。197個別関数にaccount_access_allowedの文字列がないことだけで、削除制限の迂回とは判定しない。このhookがStorageにも働くとは扱わない。

## managerの常時閲覧は直ちに不具合としない

`payment_certificate_detail_rows(uuid)` と payment_certificates SELECTはowner/admin/managerを許可し、請求閲覧featureとは連動していない。既app_v2.dartの支払証明書メニューもisManagement、表示契約も「管理者・サブ管理者」。現trade_document_sourceにも「Managers retain the original payment-reader output」の明示があり、この仕様を勝手にinvoice featureへ変更しない。

`paid_leave_worker_summary(uuid)` は本人または同会社owner/admin/manager。出勤表一覧は既メニューで「閲覧者以上」の閲覧機能、勤怠管理の編集権限は別である。RPCが返すのは付与/使用/残日数のみで、保存・承認はしない。管理者の勤怠編集feature OFFを、そのまま出勤表/残日数の閲覧禁止と解釈しない。現仕様確認だけで新しい権限狭窄を追加していない。

車両も現在のcurrent_feature_permissionsとcompany_member_vehicle_route_permission_rowsの双方がmanager常時trueを定義しており、private.can_manage_vehicle_routesのrole条件はそれと一致する。

人事P34の旧gapはrootが本作業中に適用済み。private.employee_personnel_rows / private.can_edit_worker_personnelと2 SELECT policyは更新されたため、未修正として重複計上しない。Storage固有のmanaged document policyの残りは別問題であり、PR #1437が扱う。

## LINE候補は未配備、R20の現原本が1件更新済み

既R20/R21/R22/R23/R24/R26/R28/R30 catalogの38対象を本番と比較した。37件は旧原本のbody MD5と一致。残る private.trade_document_source は後続の正規帳票改善により更新されている。R19 helperは0、r19_boundary policyも0。lineage4テーブルは存在するが、中の件数や識別子は読んでいないため、現在の実レコードに露出があるとの主張はしない。

差分は変数の追加と76行の機能追加である。保存済みの消費税行の読み取り、登録取引会社からの住所・法人番号・代表者の条件付き補完、issuer代表者の補完、保存済み子帳票がある場合の非上書きを含む。`trade-source-definition.diff` を保存した。**R20旧原本へ戻すことは禁止。旧R20 guardの単純解除も禁止。**

### R20を現bodyへ再生成する際の最小計画

1. 現trade_document_sourceの定義/OID/owner/ACL/config/MD5を再取得し、現原本としてpinする。他4対象、R19 classification helper/relations/policiesの期待状態も同時に固定する。
2. 既R20のinvoice-only boundaryを、既存認証/会社/feature条件および76行の補完機能を保ったままentryへ挿入する。payment_certificateの挙動は維持する。legacy原本やfixture stubへ置換しない。
3. 新しい補完対象のtrade_companies/partner_company_profile_extensions、保存済み子帳票、calculation_rowsの税行を合成fixtureへ加える。通常invoice、payment certificate、手入力済みappendix、曖昧/別会社/別roleのdirectory、非Master/disabled Master/正規Masterを検証する。
4. 現source全体に対してOID/owner/ACL/config保全、後段driftで全取消、正規帳票の各値とsource row digest不変、未知依存/使用後のunused復元拒否を追加検証する。既R19–30の成功範囲は再実装しない。
5. R19だけのSELECT制限では公開definer戻り値・moderator OR policy・通知enqueue・linked書込を閉じない。R20–30を含む統合境界と復旧条件を揃えてから別途本番判定する。現段階で適用しない。

## 未達

匿名/一般社員/manager/owner・admin/他社の全16bucket実HTTP、署名URL/cache失効、全197RPCの再帰helperを含む権限/機能対応と実負試験、LINE linked artifactの全経路制限、実OAuth・管理者iPhone、完全archive復旧。既41 GoTrue/Storage proof・PR1437 Native30・P34 Native46は再実行していない。試作品・source一致・private bucket・CI成功を配布前セキュリティ完成としない。

## 一次資料

Supabase skillと現公式Securing your API/Storage Access Controlを参照。Data APIのpre-requestはStorageには適用されず、SECURITY DEFINERはtable RLSを迂回するため個別の権限境界が必要。今回該当するread-only機能に破壊的変更は導入していない。

- https://supabase.com/docs/guides/api/securing-your-api
- https://supabase.com/docs/guides/storage/security/access-control
- https://supabase.com/changelog.md
