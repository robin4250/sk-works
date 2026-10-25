# 確認済みメールと第一パスワードの既存ログイン接続

固定基準 main `2ab1a420658983a682a51768852531fc3c997ac1`。対象4 source/testをGitHubから取得してsnapshot `2d7b70f` に保存した。build14凍結mainを変更せず、別認証laneの候補とする。PR1368 enrollment診断、PR1370 Apple、給与、Auth設定、既存本人sessionへ変更しない。

## 既存実装を再利用

`SecureAuthPage` に「登録済みのメールでログインする」があり、`SecureOnboardingRepository.signInWithEmail` は既存 `auth.signInWithPassword(email: email.trim(), password: ...)` を呼ぶ。signup/新identityを作らず、電話・QRログインも保持する。新しいlogin repositoryや追加token brokerは不要。

`test/existing_email_login_test.dart` の既存試験はpassword grantのみ・signup/identity書込なし、通常画面成功応答で同じ返却UIDを保持することを既に検査している。今回その試験を保持する。既存実GoTrue原本 `tool/security/login_method_enrollment_gotrue_e2e.mjs` はphone OFFのまま確認済みemailに第一pw保存→同UIDの実passwordログイン→元session/会社/Google identity/第二password fixture保持を実証する。これは隔離GoTrueで、Google identityは合成storageである。

## 最小修正

メール画面の古い「Googleで登録した方はGoogleでログイン」という説明は、後から第一パスワードを追加した本人もメールを使えないように読めるため修正する。確認済みメール＋SKOに保存した第一pwで利用可能、Googleのパスワードとは別、電話登録不要と明示する。詳しい手順は折り畳み「？」へまとめる。

アカウント設定では、サーバーで確認済みのemailが存在する場合だけ、折り畳みの次回メールログイン案内を表示する。第一パスワードが設定済みかは推測しない。#1351のこの画面の保存receipt・actor/token変更後の消去・Google/Face ID・第二pw・所属は元の処理を保持する。「？」ヘルプも同じ説明へ更新する。

本人は現在のログイン中に既存の「第一パスワードを設定・変更」を使い、認識済み確認済みemailへ保存できる。今回の候補はログアウトや再ログインを要求しない。次回必要な時に既存メールログインを利用する。実本人が保存・ログインできたとの確認はまだ得ていない。

## 一時signin検査を増設しない理由

既存 `SecondaryPasswordPrimaryVerifier` には、独立 `GoTrueClient(autoRefreshToken:false)` でcredentialを確認し、temporary sessionだけ `SignOutScope.local` で終了する原典がある。しかし本番のsingle-session設定は未読である。新たなsigninで作るsessionは、single-session設定がONなら元sessionを次回refresh時に失効させ得る。単にアプリclientを分けるだけで元sessionを保証できないため、利用者のGoogle sessionを保護する今回の設定画面へ新規の検査signinを増設しない。

電話/SMSの本番提供状態、メールprovider設定、現在本人のpassword有無も実読取/推測していない。emailが画面にあることと所有確認済みは別で、未確認emailには専用の確認済みメール案内を出さない。実SMS/OTP/メール送信、本番Auth変更、新UID作成0。

## 検証

追加widget候補3件: メール画面のGoogle既存account向け折畳み案内を開いてもHTTP0、確認済みemailだけ設定画面案内表示かつ保存receipt偽表示なし、未確認emailには表示しない。既存メールlogin成功/拒否/電話切替/QR/初回登録、Panel7 actor・receipt検査を保持。

`git diff --check` 成功。local Flutterは禁止のためanalyze/関連testsは未実行でroot remote CI待ち。UI説明の整合であり、本番メールprovider有効・本人credential保存/実ログイン完了とは扱わない。次Releaseを待つ間も、既存導線の利用は新しいコードに依存しない。

公式Supabase docsをsearch_docsで再確認:
- https://supabase.com/docs/reference/dart/auth-signinwithpassword
- https://supabase.com/docs/guides/auth/signout
- https://supabase.com/docs/guides/auth/sessions
