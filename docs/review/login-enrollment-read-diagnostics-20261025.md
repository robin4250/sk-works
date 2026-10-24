# ログイン登録の読取失敗stage（独立候補）

基準 main `22ecb36d0b15bc0fb498f3c23016508507ea5a99`。repository/testをGitHubから取得し原典snapshot `5e62e88` へ保存。PR #1368のcard/test、Apple readiness候補、給与UI、共有workflowとは別の所有範囲。

## 原因の切り分け

enrollmentは独自capability RPCを使わない。サーバー検証済み `GET /auth/v1/user` と公開 `GET /auth/v1/settings` の `external.email/phone` を読む。電話が空/未確認でもload自体は失敗しない。確認済みメール＋email提供があれば、phone provider OFFでも第一パスワードを設定できるOR契約を保持する。

Panel7の唯一の設定RPC `secondary_password_configured` はboolだけ採用し、不在/失敗はunknownへ保持する。第一パスワード登録有無のAPIではない。Panel7の「登録の有無は取得できません」はAuth公開Userにpassword有無がないことを示す定型文で、電話未登録によるload障害とは別。#1351採用済みの保存receiptがその画面での正常更新と同じ本人確認だけを示し、保存を推測しない契約は変更しない。

## 実装

`load()` だけが `LoginEnrollmentReadFailure` を返し、固定enum stageと固定の利用者向け文面を持つ。原因error/HTTP body/識別子/tokenをexceptionへ保存しない。

| stage | 境界 |
| --- | --- |
| session | 初期session、actor/tokenの保持、処理中/破棄などの既存拒否 |
| verifiedUser | 現tokenを明示したgetUser取得、別UID/匿名ユーザー拒否 |
| providerSettings | 公開settings HTTP/サイズ/timeout/JSON object取得 |
| providerShape | settings外側object取得後のexternal object不一致 |

内部 `_bound`/`_state` に任意の内部stage通知だけを追加し、`load`以外はその通知を使わない。password/phone/email操作、nonce、同じ本人/Google identity/会社役割の再検証、SMS送信・確認の契約は変更しない。stageは各load呼出し内の変数で、前回失敗を保持しない。ボタン表示だけで実登録済みにせず、provider OFF/電話空の正常結果を例外へ変更しない。

PR #1368 head `48f8db365602ce8781f0540dc877cd570f4c83ef` のcard/testを全文取得し、原典snapshot `7355c98` へ保存したdependent候補とする。既存状態表示/receipt/回復/generation制御を保持し、load catchだけを `catch (error)` として型付きread failureの固定messageへ接続する。それ以外のerrorは既存汎用文のままで、body/ID/tokenを表示しない。「？」ヘルプにも判別範囲を追記した。stage失敗時は登録状況を推測せず旧操作を表示しない。これで診断文の画面接続まで候補実装済みだが、実登録機能や本番提供状態の確認完了ではない。

## 既存実GoTrue原本と本番未確認

既存 `tool/security/login_method_enrollment_gotrue_e2e.mjs` は、隔離settingsでemail=true/phone=falseを確認し、Google-only合成identity＋空passwordから実 `PUT /user`、同UIDの実password認証、元session・会社役割・Google identity・第二password fixture不変を検証する。実Google OAuth/Face IDの成功ではない。今回この基盤や実保存を重複作成しない。

現Supabase connectorにはget_project_url/get_publishable_keys等はあるがAuth provider管理設定get/updateは露出していない。本番公開settingsの実応答も今回は未取得。shellnetwork許可外を迂回せず、provider有効化・本人session・実SMS/メール・本番Auth変更0を維持。設定不足か読取失敗かを実確認するには、次Releaseで上記safe stageを表示するか、rootの許可された読取経路による公開settings booleanの確認が必要。

## 検証

repository追加5試験はprovider HTTP失敗→phone OFF正常回復、external形不正、getUser失敗、session欠落、getUser待機中の別actor切替を検査する。exception文字列と固定messageに合成PRIVATE marker/actorを含まないこと、禁止書込なし・元/新session保持も確認する。既存credential/OTP/nonce/第一pw試験を保持。

card追加4試験は全stageの固定案内→回復、未知errorのPRIVATE body/actor/token非表示、遅い旧失敗が最新成功を上書きしないこと、dispose後失敗の破棄を検査する。PR1368の既存12試験を保持。

`git diff --check` 成功。ローカルFlutter禁止のためanalyze/関連testsは未実行。root remote CIで既存enrollment card/repositoryとPanel7 receipt試験を合わせて確認する。実機の今回の失敗stageは未受領であり、原因を推測確定しない。
