# Apple同アカウント追加の開始前確認

基準 main `22ecb36d0b15bc0fb498f3c23016508507ea5a99`。対象2 sourceをGitHubから取得した独立snapshot `ac59b54` を原典とする。完全main履歴ではない。PR #1368のenrollment card/repository/tests、給与3点、共有workflow、DB/Auth設定、通常callbackには変更しない。

## 実装した安全部分

Appleカードは公開provider状態だけで開始可能を表示していたが、直近OAuth要件が不足する長期Googleセッションでは開始後に拒否され、通常Google再ログインを促す汎用文が出ていた。今回、読み取りだけの `readiness()` を先に実行し、サーバー検証済みの同一ユーザー、元access tokenの一致、既存Google identity、直近300秒OAuth AMR、会社所属、provider提供状態を確認する。

providerの明示OFFと取得不能/不正応答を分離する。Apple identityはサーバー確認済みの場合だけ登録確認済みと表示する。開始前確認OKは本人認証/連携成功ではなく、Apple側OAuth/link開始のサーバー設定や実提供まで保証する表示にはしない。開始時の既存再検証も必ず通る。

直近OAuth証拠がない場合は、開始ボタンを出さず「同じログインを保った追加の本人確認が必要です。この接続は準備中です」と表示する。本人のログアウトや別UID作成を指示しない。提供状態は再確認でき、詳細は初期折り畳みの「？ Apple追加について」へまとめる。

読み取り中にactor/tokenが変わったら旧結果を不明として拒否する。署名済みtokenのgetUser検証より先にAMRを信用しない。カードはgenerationで遅い旧応答・dispose後の応答を破棄する。新規のsignin/refresh/session設定・OAuth URL発行はreadinessから行わない。

既存 `_checkActor` 以降の user検証、所属snapshot、AMR、`begin`、`verifyCompletion`、`cancel` 本体は原典とbyte単位で一致することを比較した。providerEnabledのbool互換入口は三値結果を有効時だけtrueに変換し、取得失敗を許容しない。

## 実装しないまま残る同session再認証

既存調査 `5ad866a` / `3aa5968` の境界を引き継ぐ。通常 `signInWithOAuth` はアプリsessionを置換し得る。独立OAuth clientでもsingle-session設定では元session保持を保証できない。汎用OAuth AMRとGoogle identityの存在だけで、challengeに対応したGoogle本人再認証の証拠としない。

既存サーバーには、元actor/session＋Google subject＋Apple link操作＋独立PKCE/callbackへ固定するchallenge、proof発行/一回消費、GoTrue link開始との接続がない。これを新token brokerとして無断追加しない。password proofやFace IDをOAuth要件の代わりにせず、AMR条件も削除しない。

従って今回の変更は開始前の安全な状態確認・不可能な操作の停止までを完了させる候補であり、長期GoogleセッションのままApple再認証が完成したとは扱わない。実装継続には上記サーバー契約の採用判断と、元session refresh生存/別actor・subject拒否/遅延callback拒否/同じ会社役割保持の隔離実証が必要。本番Apple/manual-link設定確認と実Apple本人操作はroot側の別工程で、給与Releaseを待たせない。

## 検証候補と未実行

source専用8 tests: read-onlyでの開始前OK、古い/未来AMR拒否、provider OFFと読取失敗の区別と回復、異なるserver actor/Googleなし/所属なし拒否、server identityでのlinked、待機中の別actor/同actor token変更拒否。禁止Auth routeや非GET呼出しがなく元tokenを保持することも検査する。古いAMRでは既存beginも拒否してURLを開かない。

card専用4 widget tests: disabled/unknown/proof不足の別表示、再確認中の旧ボタン除去と回復、linked時に開始しない/ヘルプ、dispose後遅延結果の破棄。

`git diff --check` と既存securityメソッドのbyte一致比較は成功。ローカルFlutter禁止のためanalyze/12 testsは未実行。rootが対象source2/test2をremote CIへ載せ、既存login/enrollment/panel-seven試験とともに検証してから統合判断する。合成MockClientによる検査であり、実GoTrue署名/OAuth/本番/端末の証明にはしない。

公式Supabase `search_docs` で https://supabase.com/docs/reference/dart/auth-linkidentity と https://supabase.com/docs/guides/auth/auth-identity-linking を再確認。公式identity linkingはログイン済みユーザーへの追加であり、この候補独自proofを受け取る引数は追加していない。
