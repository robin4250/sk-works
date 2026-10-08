# 通知受信者の削除アクセス制限（本番 OFF）

基準 main: `72bb71e77c396394256839fdb1bb54ef7f8d1868`。#792 の停止受信者 business helper に、既存の削除受付後アクセス制限を追加する。共通認証、RLS、削除実行、登録済み選択、通知重複防止台帳は変更しない。

## 読取確認した既存本番契約

2026-10-09 JST の read-only metadata 確認。登録ユーザーの行は取得していない。

- `private.account_deletion_access_restrictions`: postgres 所有の通常テーブル、RLS 有効、force RLS 無効、policy なし。
- 列は `user_id uuid NOT NULL`、`job_id uuid NOT NULL`、`restricted_at timestamptz NOT NULL` の3列。
- `user_id` primary key、`job_id` unique、job_id は private.account_deletion_jobs(id) を参照。
- ACL は postgres 全権限、service_role SELECT/INSERT。anon/authenticated の SELECT はなし。
- `private.account_access_allowed()` は SECURITY DEFINER / search_path 空で、auth.uid() 自身に制限行がないことを確認する。対象受信者の評価には使えないため、auth.uid() を偽装せず対象 user_id を直接 helper 内で照会する。

## 変更と適用条件

専用 migration `20261008211227_source_notification_restricted_recipients.sql` は既存テーブル、所有者/RLS、正確な列、クライアント SELECT 不可、先行 helper を確認し、契約が異なる環境では停止する。テーブルを新設したりアクセスを広げたりしない。

受信者 helper は会社所属と active worker（または worker 未登録 owner/admin）を維持し、その受信者の削除アクセス制限がある場合に false を返す。既存 setter/getter/発行/対象導線はこの helper を使う。保存済み選択は残し、候補から除外し、発行を止める。既に作成された通知と台帳も消さない。

## 検証

実 migration を実行する隔離 PGlite 検証で、テーブル未存在・余分な列・client SELECT 権限の不一致は停止することを確認。利用可能な管理者 caller と制限された active recipient を分け、車両/日報通知が発行されないこと、候補/setter/対象導線の拒否、選択と通知/台帳の保持、role/status 不変、匿名アクセス拒否、rollout OFF 時の発行なしを確認した。

実行: `node tool/verify_source_notification_restricted_recipients.mjs /tmp/sko-sql-runtime/node_modules/@electric-sql/pglite/dist/index.js`。CI 結果は PR を参照。

## 状態

コード・隔離検証を準備済み。本番 migration 未適用、rollout OFF。削除フロー全体の完成、実機通し確認、外部メール送信、TestFlight 公開を意味しない。#792 の通知発行 UI 接続などの残作業も別途管理する。
