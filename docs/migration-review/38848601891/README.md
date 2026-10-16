# 未導入migrationのレビュー証拠

**本番未適用・deployable:false。正規supabase/migrationsには配置していません。**

Supabase CLI 2.121.0の実際の `supabase migration new` が生成した名前とSQLを保存しています。保存名には実行防止用の `.review-only` を付けています。timestampは手作業で作成していません。SQL本体は固定staged sourceとbyte完全一致です。

| 証拠 | 値 |
|---|---|
| 生成PR | [#1101](https://github.com/robin4250/sk-works/pull/1101) |
| run | [38848601891](https://github.com/robin4250/sk-works/actions/runs/38848601891) |
| artifact | 12024217975 / reviewed-staged-migrations-38848601891 |
| ZIP SHA256 | ecbbaa6df53c3da61f65fd419be1c8eb374a99bd831a227861499e9165b361bd |
| artifact期限 | 2026-11-15 04:03:42 UTC（30日保持） |
| CLI / setup action | 2.121.0 / 3c2f5e2ae34c34e428e8e206e2c4d21fa2d20fbf |
| 請求通知source | #1097 / bde05a64af4e2150372bde4ca1c1e31c08eebfd0 |
| 現場ID source | #1098 / df73d422c91bdc8bfd55d1138aff77c987c8f705 |

## 実CLI filename

- `20261016040338_invoice_month_end_approval_notifications.sql`
- `20261016040341_site_identity_links.sql`

保存先は各 `migrations/<実CLI filename>.review-only` です。verification-manifest.jsonはartifactの原文で、filenameは実CLI名を保持します。manifestのworkflow_commitはPR実行時のGitHub合成merge SHAで、固定source SHAとは別です。

## 独立検証

ZIPをGitHub connectorから取得し、ZIP digest・パストラバーサル不在・実CLI名・manifest・help・隔離ログを確認しました。さらに固定SHAのGitHub元SQLを再取得し、元SQL・artifact source・生成SQLのbyte完全一致とSHA256一致を検証しました。`sha256sum -c SHA256SUMS` でこの証拠一式を検証できます。

隔離PGlite 0.3.14の請求通知テストは月末・通知証跡・登録版・ACL・定義driftを検証し、現場IDテストは受信証跡・旧ID/実績・CAS・権限拒否・複数方向共有・会社票・安定tieを検証しています。成功ログをlogsに保持しています。本番データは使用していません。

## 導入制御と残件

- 請求通知は会社別rollout default false。SQL内で会社を有効化せず、cronを登録しません。
- 現場IDにはrollout機構がありません。適用すればowner/admin向け認証RPCが有効になるため、rollout_control=not_present・deployable:falseのままです。両方OFFとは扱いません。
- 本資料の保存は導入承認ではありません。通知時刻・cron運用、現場IDの段階導入、staging権限/advisors、現在の関数定義drift、前提schemaと業務接続は別途確認が必要です。
- 正規migrationへの配置は、別レビュー後にbyte一致を再検査して別commitで判断します。既存source・既存migration・UI・給与・本番DBは変更しません。

監査時main 565a1a2c1fb704fdce91c58efd4d57fc0bce8f91のworkflow108件には本番migration自動適用経路は見つかりませんでした。外部Supabase連携設定や手動CLI運用は監査対象外です。

[Issue #273 独立検証記録](https://github.com/robin4250/sk-works/issues/273#issuecomment-6207872253)
