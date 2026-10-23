# Apple再ログインの前提となる新規UID作成防止

確認元 main: `52e81c15b97edbc5ffedfb346e02df98e622e6c2`。

Google既存所属チェック、メール/電話パスワードログイン、設定画面のApple identity追加は既に存在する。未提供Appleログイン入口を追加するだけでは本人アカウント保持要件を満たさない。所属照会はデータ進入を拒否できても、OAuthによる新規Auth UID作成を防がない。

この候補は、Supabase公式の before-user-created provider別signup拒否をAppleへ限定するもの。Authが渡す `app_metadata` を読み、利用者が編集できる `user_metadata` は判定に使わない。新規Apple/曖昧または欠損providerを拒否し、Google/email/phoneの正しいeventを保持する。既存アカウント・会社・役割・パスワードを読書きしない。公開APIではなくAuth専用の非公開schema関数とする。

## 検証と適用条件

SQL fixtureは合成eventと権限の検証であり、実Apple本人認証・GoTrue hook呼出し・identity linking・既存Apple再ログインの証明ではない。ローカルPostgresがないため本時点では未実行。CIでNative PostgreSQL上のfixtureを実行後、隔離GoTrueに接続して通常signup/login/既存連携の保持を確認する必要がある。

本番に自動適用しない。既設定hookの有無と原本を確認し、既存hookがある場合は置換せず既存判断へ合成する。登録hook URI、private schema権限、元設定と限定復元方法を確認する。Apple provider・manual linking・Apple Developer Services ID/secret・厳密callbackは別条件。未連携Appleの新規作成拒否と既存Googleへ明示追加後の同一UID再ログインを実証してから入口を公開する。

既存のGoogle/Face ID利用は保持する。本人をログアウトさせたり、パスワード生成/再設定、メール一致による会社移管、既存ID作り直しで代用しない。

公式確認: https://supabase.com/docs/guides/auth/auth-hooks/before-user-created-hook （search_docsでprovider別拒否仕様を確認）。
