# 資格直接管理：OFF導入・未使用復旧のレビュー

本番への書き込みは未実施。新しい管理者操作を本人写真の申請へ代理送信しない。情報編集・資格削除・保存済み写真の並替／表示からの削除は承認待ちを追加せず直接反映する。新規写真バイトの追加・差し替えはまだ無効。

## 変更と影響

追加：private のOFF状態・管理操作監査、正規管理者判定、直接管理RPC、公開invoker wrapper。既存資格・写真・申請関数・履歴の本文と保存値を変更しない。正式行の編集／削除に既存の履歴triggerを使い、管理操作の全snapshotも別の追記専用監査へ保存する。

既存 worker_qualifications の UPDATE/DELETE に restrictive policy を加える。現在の同社 owner/admin/manager、people権限、有効セッション・利用可能アカウントを必要とする。一般社員に誤ってpeople機能を与えても、この管理UPDATE/DELETEは許可しない。本人の初回登録INSERT/SELECTと既存本人写真承認のSECURITY DEFINER処理は変更しない。

既存の管理資格追加フォームは再利用する。新契約が不存在の場合だけ旧追加方式を維持する。新契約が導入済みOFF・未知応答・アクセスエラーのとき新管理APIから旧方式へ迂回しない。保存結果が不明なら固定IDの監査結果を再照合し、OFF後も既存結果を取得できる。

## 導入前照合

catalog-query.sql は既存の関係・列・FK・trigger・policy・認証/helper関数を指紋化する。business-query.sql は既存資格・正式履歴・写真履歴・申請・従業員・資格マスター・所属・機能権限をDB内で指紋化し、実値を出力しない。

取得した現在値を prepare-guards.py へ渡すと単一トランザクションの install-off.guarded.sql.review-only を生成する。既存8テーブルをロックし、適用前のcatalog/businessを完全照合。追加後も原データの指紋不変と新状態OFF・操作0件を確認する。導入中に関連データが更新されていれば適用しない。

ローカルに生成済みのinstallは読み取った本番指紋に結び付くレビュー用候補であり、将来の最新状態への無条件適用用ではない。main統合・対応Release・バックアップ・既存権限差分をrootが再照合してから扱う。

## 未使用復旧

OFF導入直後にcatalog-query.sqlを独立して再取得する。その installed catalog と導入前のcatalog/businessを prepare-guards.py の `--installed-catalog-md5` へ渡すと、具体的な restore-unused.guarded.sql.review-only が生成される。

復旧は状態OFF・操作0件・関連データ不変・導入後catalog完全一致が必須。同一トランザクションで追加policy/関数/表のみをRESTRICTで落とし、元catalogとbusinessへ正確に戻ったことを確認する。2回目の復旧・後続変更・監査使用後は拒否する。使用後は状態をOFFにして監査と既存データを保持し、表を消して旧方式へ戻さない。

復旧SQLの実本番installed fingerprintは本番未導入のためまだ存在しない。Native/PGlite fixtureでは実際の導入後catalogから生成して復旧・再導入・使用後拒否を検証する。Nativeでは、処理中の操作とOFF更新が相互に待機し、新しい操作がOFF確定後に拒否されることも2接続で確認する。合成fixtureの成功を本番復旧成功とは扱わない。

## 残る本番条件

実GoTrue/実Storage・iPhone、管理者の新規写真送信契約、既存監査の保持期限／消去手順と閲覧画面の整合は未確認。これらをコード完成やCI成功で代用しない。旧独立承認試作 #1493 と旧 saved-photo approval guard をこの機能へ併用しない。

Native/PGliteのセッション境界は本番から読み取った require_reauthentication_session と account_deletion_barrier_key の実関数本文を使う。Auth.users/sessions/JWTは合成で、BAN・匿名・失効・他人session IDの拒否を検証する。実GoTrueの署名検証成功ではない。

配布前のretry個人情報保護は pending-privacy.md のv2仕様を必須とする。端末への全文保存はしない。サーバー本文の15分期限と毎分purge、直近cleanup成功を確認するまでcapabilityは有効にしない。既存本人写真申請の保存方式はこの補修で変更しない。
