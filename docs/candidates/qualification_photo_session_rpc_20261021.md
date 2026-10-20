# 資格写真申請の固定token・session scope RPC adapter

基準 `5f610acf0c431a8a5e39cbe8ecb6dbd9435beee7`。新規 `qualification_photo_session_rpc.dart` と `qualification_photo_session_rpc_supabase.dart` のみで、既存submission/core/SQLite/pubspec/製品routeを変更しない。default OFFの未接続adapterであり、モバイル削除を有効化したものではない。

## 接続interface

既 `AdminSavedQualificationPhotoSubmissionRepository` の `scope` / `scopeChanges` / `authorization` / `rpc` へ、adapterの同名tearoff/getterを渡す。durable pending storeは別adapterをそのまま渡す。固定requestの生成・永続化・CAS・不明結果のget確認・receipt解釈は既repositoryの責務を保持する。

- pure guardのsnapshotはactor/company/target/accessToken/activeをメモリだけに固定する。tokenを既pending JSON・ログ・docへ保存しない。snapshot.toStringはredacted。
- Supabase wrapperは `SupabaseClient`、選択中scopeのgetter/stream、foregroundのgetter/streamを必須入力として受け取る。実pageは会社・対象変更と全非foreground状態を漏れなく伝える必要がある。wrapper自体は製品route・WidgetsBindingObserverを追加しない。
- scopeは開始時選択actorとAuth session.user.id一致、非期限切れsession、active、foregroundを必要とする。明示的 `enabled:true` がなければRPC0。
- constructorはclientを作成しない。provider設定・ログイン・ログアウト・refreshSession・setSessionを呼ばない。

## 失効と送信境界

- Auth event、会社/target event、foreground eventの値そのものを観測する。同じgetter値へ戻ったABAでも、途中の不一致を観測したguardは復活しない。
- token更新（同一actorのrefreshも含む）、actor/company/target変更、非foreground、signedOut、stream error/done、disposeはsticky失効。各awaitの前後で現在getterも照合する。期限切れは次の操作時にも再検査する。
- 失効時はscopeChangesへactive=falseを1回通知し、既submission repositoryも失効させる。遅れて届いたcapability/readiness/data応答は返さない。
- transportは既 `personal_qualification_submission` 1関数だけ。`p_action` / `p_data` と固定 `Authorization: Bearer <captured token>` をリクエストごとに設定し、SDKの後から切り替わった既定JWTへ任せない。
- 読取は `admin_saved_photo_capability` と `admin_saved_photo_prepare_readiness` の専用契約のみ。data RPCは `prepare_admin_saved_photos` / `get_photos` / `submit` / `cancel_photos` のallowlist。approve/reject、旧personal prepare/capability、Storage操作、資格DELETE、任意RPC名への入口を作らない。
- 各data RPCの直前に最新capability/readinessを2読取し、会社/actor/対応版/管理可否を既parserで検査する。False/欠落/旧版は閉じたまま。クライアント確認がserver認可やbaseline CASの代わりになるとはしない。
- prepareは固定company/target、他操作はidだけを許可。復旧後の初回submit/cancelは先にgetでid/requested_by/target_idが当該actor/targetであることを確認する。別対象のreceiptで書き込まない。guard内もdata operationを直列化する。
- paramsをreadiness await前にJSONコピーし、callerが元Map/写真Listを変更しても送信対象を変えられない。返却receiptのid/actor/targetを検査した後、詳細status/写真順序/履歴は既repositoryの厳格parserへ渡す。

## 検証範囲

`dart tool/verify_qualification_photo_session_rpc.dart`：171 assertions成功。Flutter起動、network、本番、SDK初期化なし。固定関数/Bearer、default OFF、scope/token/背景ABA、stream失効入口、polling検知、遅延readiness/dataの拒否、専用gatefalse、allowlist拒否、別target/actor receiptではgetだけ、mutable payload、同時RPC、disposeを検査。

既submission repositoryを実際にpure guardへ結線する追加fixtureで、prepare→get→submitのreceipt確認、pending storeへtoken不保存、token更新後のrecover RPC0を確認した。fixtureのstoreはメモリで、durable実装の代用ではない。最初の実行はcomposition fixtureのcurrentSavedPaths引数不足でコンパイル停止し、既interface通りに修正後成功。

SDK wrapperはDart formatterによる構文読取のみ。現環境はFlutter起動が自動承認レビューで拒否されたため、Flutter/実SDK HTTP試験は未実施。親担当のCIで固定SDKの型解析とactual SDK loopback HTTP（明示Authorization、Auth A→B→A、refresh event、streamerror、foreground変化）を確認するまではproduction-readyとしない。

## 残条件

- lifecycle/scope stream、durableCAS store、専用readinessが本番対応していること、正規権限付きprepare/submit/get/cancelへの実HTTP接続、UI選択/確認/結果表示の接続。
- invalidateは送信済みHTTP/server COMMITを取り消さない。結果不明時は既repositoryの同一request確認を維持し、新requestで自動再送しない。
- refreshを観測した場合も新tokenへ自動付替しない。画面を開き直し新guardを作り、同actor/company/targetのpending commandを正規に再確認する。
- selected company/targetや背景イベントをcallerが通知しなければ途中ABAを観測できない。getter前後照合はその代替保証ではない。mobile上のbinding接続を別途検証する。
- 実本番/Auth/RLS/provider/Storage/金融行/Mac/iPhone/他者送信の操作0。

## 照合した資料と既実装

- `lib/features/auth/secure_onboarding_repository.dart`：固定accessTokenと明示Authorizationの既パターン。
- 固定submission repository/capability/readiness parserの既interface。
- Supabase changelog（2026-10-12 TLS旧cipher廃止予告を確認。今回TLS/provider設定の変更なし）。
- https://supabase.com/docs/reference/dart/rpc
- https://supabase.com/docs/reference/dart/auth-onauthstatechange （onErrorを必ず扱う指示を確認）。

## 継続：global lintと実SDK loopback fixture

親担当の既専用CI39513633171は成功、global Flutter CI39513633195は新guard/verifierの6 infoで失敗したと報告を受領。ifのblock、toolからlibへの4importをpackage形式へ、printをstdoutへ最小修正した。製品動作やgateは変更しない。ローカルはpackage_configにsk_worksのsourceだけを指定しpure171 assertionsを再実行して成功。Flutter起動・依存更新・pubspec変更なし。

新 `tool/verify_qualification_photo_session_rpc_sdk_test.dart` は固定Supabase SDKを使う実HTTP fixtureを4testに限定して用意する。loopback IPv4のランダムportにだけ送信を許すhttp.ClientをSupabaseClientへ注入し、他host/scheme/portの要求はsocket送信前に拒否する。サーバーは既RPCのPOSTだけを受け、全認証値は合成fixture値である。AuthのsetInitialSessionは合成ローカルsessionを設定するために使い、本番ログイン/ログアウト/provider操作をしない。

1. 実SDKのrpc/setHeaderによる固定Authorization・単一既RPC・scope一致receiptと、その後token変更時の追加RPC0。
2. 実HTTP readiness応答を保留中にtokenを変更し、旧応答を拒否してprepare write0。
3. wrapperのforeground/会社streamがABAでも失効を保持し、HTTP0。
4. 実SDKのget応答が別targetならsubmit/cancelを送らない。

SDK fixtureはlocal Flutter禁止を維持して未実行。型解析と実行は親担当の専用CIに `dart analyze ... tool/verify_qualification_photo_session_rpc_sdk_test.dart` と `flutter test tool/verify_qualification_photo_session_rpc_sdk_test.dart --reporter expanded` を追加して確認する。fixtureを用意したことを実SDK検証成功・mobile接続済みとしない。既171 assertionsと同じ疑似transportをもう一度測るfixtureではなく、未実証だったSDK HTTPの境界を測る。
