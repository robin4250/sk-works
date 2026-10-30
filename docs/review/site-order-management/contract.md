# 現場管理・注文書共有（実装途中、未接続）

## 今回の指定

- 取引会社から現場情報と押印注文書を一緒に受け取り、現場管理で保管する。
- 管理者またはサブ管理者の承認で保存する。フッターの「現場」へは金額を含まない現場情報のみを追加する。
- 現場を開くと「注文書を見る」「注文書を作る」。閲覧はピンチ拡大縮小。
- 作成は既存の正式デザインのプレビューへ入力し、確定後に登録済み協力会社をプルダウン選択して共有送信する。
- 送信前に会社名・単価・単位をポップアップで再確認する。複数明細なら全明細を省略せず表示する。選択画面と確認画面の両方に「入力画面に戻る」を置く。
- 過去注文書は全件を工事名称・工期で一覧にし、名称を表示した全画面で左右スワイプ、ピンチ拡大縮小。閉じるボタンは固定表示する。
- 注文書は押印した保存版を扱う。
- 注文を承認した場合、承認と同時に請書を元の取引会社へ返送する。
- 取引会社側では「協力会社登録」の協力会社名タップから、その会社個別の注文書
  ページを開き、注文書・返送請書・過去履歴をまとめる。現場別表示と会社別表示は
  同じ正規原本を参照する。
- 受信、承認待ち、承認・拒否の結果、返送請書の受信は既存の「要通知」に届く。
- 後続訂正：現場に関する新しい注文書の作成は現場管理で行う。協力会社個別ページは
  注文書・請書・過去履歴の閲覧をまとめる入口で、作成ボタンは設けない。
  協力会社登録詳細の重複「注文書生成」ボタンを除去する候補を追加した。
- 最新指定は、取引会社登録の「注文請書生成」も会社詳細から移動し、独立した
  「注文・請書」ページに「注文書生成」「請書生成」の2操作を置く。
  管理者・サブ管理者が利用する。会社登録/編集は残す。単独生成は既存正式editorを
  再利用し、現場archiveの未接続と切り分ける。hubにもmaster ON/OFFを適用する。
- 注文書・請書統合にはマスター限定ON/OFF。初期OFF、欠落/取得失敗もOFF。
  管理者/サブ管理者からtoggleしない。OFF時は新作成・編集・共有・承認による
  自動請書返送を停止し、保存済み原本・履歴の閲覧を既存権限で維持する。

## 現在の実物

ベースは main de9bbfafde2d5cd2661d913583e55af3ab11a038 と同じ tree の
eaaf95001。既存 `site_share_approval_page.dart` と `site_cloud_repository.dart`
には `site_share_inbox` / `respond_site_share` があり、承認後に自社 `sites` を
作る。既存 `send_site_share` は明示ホワイトリストで住所等を共有し、単価は含めない。
この経路を置き換えず拡張する。

管理者向けの実際の入口は `AdminSiteFinancialPage`、フッターは別の `SitePage`。
画面名だけを見てフッターへ注文書や金額を接続してはならない。

`StandaloneTradeDocumentRepository` は read-only registration context。
正式な PDF 生成はあるが、現場に紐づく保存済み押印 PDF アーティファクト、
受信・再読込・共有送信・全履歴 API は未接続。既存の双方押印による現場金額調整は
別の契約承認であり、単体注文書をそこへ黙って読み替えない。

## この変更で用意したもの

- 独立した注文書送信 state machine。会社・本人・セッション・現場・押印PDF版・
  相手会社の接続版を確認。入力確定と送信再確認を区別する。
- 保存結果不明では成功表示せず、新しい送信操作を停止。同一 request ID の receipt
  照合のみを許可する。送信前の durable intent 保存を adapter の必須契約にする。
- 協力会社選択と明細全件の再確認画面。
- 工事名称・工期一覧、左右スワイプ・ピンチ・固定閉じるを備えた履歴画面候補。
  保存PDF SHA-256を照合してから描画する。PDFを再生成して原本を差し替えない。
- private archive の構造候補 SQL。全テーブル RLS、クライアント grant なし、
  原本・配送・応答は append-only。SQL末尾は ROLLBACK。
- 会社個別注文書ページの候補。未接続の保管機能は準備中と表示し、
  従来の会社情報編集等へのボタンを保持する。現在の会社名タップは
  従来どおりであり、未完成ページに差し替えていない。
- 原本会社/現場/帳票種別をcompound FKで検証する構造候補、承認と請書の元sender返信
  intent DTO、価格やURLを含まない通知envelopeのstrict mapper、通知event宛先/重複検証。
- 原本には受注会社ID・正式名・発行側の登録trade ID・server発行の接続fingerprintを固定。
  選択先の4項目と一致しない送信、請書の会社IDが逆方向でない承認を拒否する。
- master capability はarchive閲覧とmutationを分離し、必要なserver各契約版が全部1の
  ときだけ新操作を許可する。DTOの一致は実認証・実権限を証明するものではない。
- 新package向けの非金額現場projectionを用意。price/PDF/会社情報snapshotだけでなく、
  金額を含み得るfree-form notesも引き継がない。既存の一般site_shareは変更しない。

**これらは本番ルートから未接続。受信保存・送信が完成したという意味ではない。**
API不在をスタブ成功に変換せず、既存サイト共有や会社情報を変更していない。
Draft PRはmerge blocked。新しい独立hub/現場管理の作成経路が未接続なまま、会社登録の
旧入口除去候補だけをmainへ統合・実機配布してはならない。

## サーバー接続に必須の残作業

1. 正式帳票担当と共通の trusted artifact issuer を用意する。サーバー側で会社・
   現場・登録角印の使用権、会社情報スナップショット、正式版の契約条項、
   明細・単価・単位、保存PDF実bytesのSHA-256と長さを検証して immutable receipt
   を発行する。client の `sealed:true`、hash、価格文字列だけを信用しない。
2. availability RPC は complete な artifact / archive / sharing / approval /
   recovery contract の版がそろった場合だけ利用可能を返す。未導入、取得失敗、
   権限不明では新しい保存・送信ボタンを有効にしない。
3. 既存 `send_site_share` と同一TXで pending package を作る。保存前に現在の
   actor・live SID・会社・管理権限・登録協力会社・accepted connection・接続版・
   source site・artifact revision/hash を再確認し、idempotency request ID の
   同一内容リトライだけを既存 receipt として返す。別内容の再利用を拒否する。
   user操作順は「入力draft確定→登録協力会社選択→その宛先入り最終押印原本prepare
   →単価/会社/原本版の再確認→共有」。相手の選択前に完成した原本として扱わない。
   `SiteOrderSendPage.prepareWorkflow` は選択後にだけ呼ばれ、saved draft ID/revision、
   正規trade ID、expected peer company ID、expected connection fingerprint、同一request
   IDを使ってserverでCASするadapterが必要。返却された原本が選択先と異なると、
   確認popupを出さず送信も行わない。
   company_connectionsには整数version列がないため仮の1を使わない。サーバーが
   connection ID/status/updated_at、正規trade ID/linked company/role/status、会社正式名
   からopaque SHA-256 fingerprintを発行し、その値を比較する。clientがPostgresの
   JSON表現を再計算して別hashに置き換えない。会社名・登録リンクの変更は新原本版を
   準備して再確認する。保存済み旧原本の会社名やhashは書き換えない。
4. 既存 `respond_site_share` の保護を保った package-aware 応答を用意する。
   管理者/サブ管理者かつ recipient だけが、同一 pending package と押印版を承認。
   サイト作成と archive response を同一TXで完了し、片方だけ保存しない。
   古い `respond_site_share` 単独では package を部分承認できないガードが必要。
   同じ承認TXで、incoming orderの正確な版/hashに対する自社押印請書を生成・保存し、
   元のsender取引会社だけを宛先とする durable acceptance outbox を必ず作る。
   承認、現場の非金額projection、private注文書保管、請書返送intentは一括commit。
   実配送の完了は別statusとして記録し、配送失敗で承認済みを未承認へ戻さない。
   再試行は同じoutbox IDを照合し、二重返送しない。clientの承認成功callbackから
   任意会社へ追加送信する方式は不可。承認成功を配送完了とも表示しない。
5. 一般 `sites` / notes / 地図 / チャットの公開欄に価格・注文書payload・PDF URL・
   秘密の storage path を入れない。既存 directory RPC に archive join を足さない。
   押印PDF、会社情報原本、単価を protected private archive に保管する。
   旧site_shareのnotesは自由文なので、新packageの承認projectionへそのままコピー
   しない。新しいpure DTOの許可fieldとserverの実際のprojectionを一致させて試験する。
6. protected workspace RPC は live SID、現会社、`can_view_admin_site_data` または
   既存管理権限を再確認し、sender/recipient の正規現場リンクを検証する。
   全件履歴は cursor pagination、重複なく欠落なく取得する。
7. クライアントadapter は scopeChanges に auth/会社/対象書類版だけでなく金額閲覧
   権限撤回も流し、各await前後に scope を検証する。閲覧中に撤回したPDFを破棄する。
8. durable intent は端末の既存保護ストレージへ送信開始前に保存し、再起動時に
   current actor/SID の pending だけを照合する。logout・他会社へ情報を持ち越さない。
   画面内state machineだけでは再起動後の recovery は完成しない。
   未解決intentがある同じactor/会社/現場/原本/相手への新しいmutationをadapterで
   拒否し、既存request IDの照合へ案内する。「閉じて後で確認」は画面だけを閉じ、
   durable intentを消去しない。画面を開き直して新request IDで再送する迂回を防ぐ。
9. admin現場詳細へのボタン、受信箱と全履歴、既存プレビューeditorからartifact保存
   →協力会社選択へのreturn値を接続する。正式帳票共通ファイルは別担当へ一本化。
10. `trade_company_page.dart` の協力会社名タップは専用ページの候補を準備した段階。
    正規一覧APIがそろってavailabilityを確認できるまで従来の詳細画面を維持する。
    登録会社IDとcanonical company connectionで集約し、
    会社名一致で履歴を混ぜない。通知は `notifications_page.dart`、
    `notification_target_policy.dart`、`notification_explanation_page.dart` が既存接続点。
    新しいevent種別はサーバー側通知許可schemaと同時に追加し、deep-linkは通知IDから
    serverでactor/company/order/revisionを確定する。届いた通知を開くだけで承認しない。
    package受信/承認待ち/承認拒否結果/請書受信を immutable event outbox に保存し、
    unique event ID・宛先で重複通知を防ぐ。既存site_share_approvalとは別契約であるため、
    新機能を旧キーへ偽装して部分承認を誘発しない。
11. master側の既存 `MasterFeatureControlsRepository` /
    `current_master_feature_flags` / `set_master_feature_enabled_with_proof` を再利用する。
    新keyは暫定 `site_order_documents`。実際のregistry CHECK・supported key・proof
    検証定義を照合したguarded拡張が必要。`private.require_master_optional_feature`
    はvehicle/route専用で欠落行=ONという旧契約なので、そのまま転用しない。
    mutation APIと配送workerは同じlive master gateを確認する。既にqueue済みの
    請書はOFFで消去せず保留を記録し、ON後も同じoutbox IDで照合・再開する。
    actor権限撤回/設定変更の競合試験、配送中の結果不明と未配送の区別が必要。

## 検証状態と本番条件

Flutter SDK はこの作業環境にないため、追加 Dart / widget 試験の実行は CI で確認する。
PDF native raster、ピンチと左右ページのgesture競合、iPhone起動・小画面・文字拡大は
未確認。12ページ/20MiBを超える保存PDFは切り捨てず、表示できないことを明示する。
adapter の一覧 pagination が未完了なら「全履歴閲覧完成」と報告しない。

構造SQLのオフライン試験は別 proof に記録する。認証・セッション・現場共有の実物を
置き換えたfixtureだけで live authorization 成功とはしない。
本番DML/DDL/RLS/Auth・配信・実機更新は未実施。個別書類免除はOFFを維持する。

2026-10-30 オフライン PGlite: `verify_site_order_archive_schema.mjs` は **43 checks
passed**。正規の注文→自社請書outboxと承認の整合、元の取引会社以外への返送拒否、
別会社artifact/別現場参照拒否、request ID重複拒否、原本更新/削除拒否、RLSと無grant、
通知宛先/応答整合/重複拒否、単価明細の型・負数・小数・未知キー、原本と異なる
宛先・旧会社名・別登録trade ID・変更済み接続fingerprintの拒否を確認。
このSQLは構造候補であり、trusted issuer・RPC・live session・実配送は試験対象外。
