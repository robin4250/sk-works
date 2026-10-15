# 現場契約：保存処理の反映・再開手順

更新：2026-10-15。これは開発作業用の引き継ぎで、利用者画面の説明ではない。

## 対象と現在地

- PR #1065 の確認画面・実会社印プレビュー・送信・承認は main `e42ed70cf3cdc5ca3e5af615548efe18764067cd` へ統合済み。同じ版と会社印で照合する。
- PR #1068 の migration と本手順は main `3db6e2bf04c113970ac5c6bc08317b0dc281af95` へ統合済み。source は Supabase CLI 2.121.0 の `migration new` で生成した `20261015080425_site_contract_sealed_revision.sql`。
- migration は `tool/staged/site_contract_sealed_revision.sql` とバイト単位で同一。SHA256 は `5581fb8066792cf63400d22039fb89e90330b72b00e91a6c85943cc931245da3`。
- #1065 は head `1ea` の全7 checks（Flutter / iOS Release / PGlite / 実 PostgreSQL の競合検証を含む）の成功後に統合した。以後の動作変更にはその版の検証が必要。
- 本番は公式 `apply_migration` で反映済み。公式履歴 `20261015083346 site_contract_sealed_revision` は上記 source に対応する。二重適用や履歴の改名はしない。
- 「文書追加時点では未本番・全体 CI 中」は反映前の過去状態。現在はアプリ・migration の main 統合と本番反映が済んでおり、利用設定 OFF と下記の未完了項目は別に残っている。
- 利用設定は初期 OFF を維持する。実押印・実承認・実通知を開発ツールから作成しない。
- 通知 outbox は配送完了を意味しない。通知配送、契約書 PDF、適用日別の請求計算、実機確認は別の未完了項目。

### 2026-10-15 本番反映後の確認記録

- 新規 seals / notification outbox、既存の提案・確認・rollout は各0件。rollout は OFF を維持し、実押印・実承認・実通知は行っていない。
- 新規 private 表の RLS・直接アクセス拒否、公開 RPC の anon 実行拒否を確認した。
- 実ユーザー・実対象を使わない未ログイン確認で workspace / preview / send は `42501`、approve は nil 提案に対する not found で拒否された。これは実ユーザーによる押印・承認の動作確認ではない。
- 下表の既存4関数の定義 MD5・ACL、既存会社2件・通知33件の内容は反映前後で不変。
- security advisors は INFO 127 → 129。既存 WARNING の件数 158 / 1 は変わっていない。

以上は反映時点の記録であり、将来の件数や状態を保証しない。再開時は適用済み履歴を確認し、必要な未完了作業へ進む。

## 反映前

以下は未適用の変更を反映するときの手順。今回の migration は反映済みなので、再開時に同じ SQL を再実行しない。

1. Issue #273、最新 main、#1065/#1068 の最新 head と検証結果を確認する。既存差分を破棄したり main を巻き戻したりしない。
2. 本番への変更担当を一人に固定する。ほかの担当は隔離データベースだけで検証する。
3. 既存契約関数の定義と ACL、関連表の件数・内容 digest を退避する。会社・帳票・通知等の実データは出力や Git に含めない。
4. 同名の新表・新関数・migration が既に適用されていないか確認し、二重適用しない。
5. security advisors の各項目の `count` を記録する。配列の項目数と検出件数を混同しない。

2026-10-15 の読取確認では、既存の提案・確認・rollout は各0件だった。この記録は将来のデータ不存在を保証しない。反映直前に取り直す。

既存の private 関数は変更しない。2026-10-15 の `md5(pg_get_functiondef(oid))` は以下。

| 関数 | 定義 MD5 | 実行 ACL |
|---|---|---|
| confirm_site_payment_terms | 51f0c18b2da44cdd9757714cc88c5695 | postgres, authenticated |
| document_company_seal_snapshot | 3e234262cc53a7b6c255db51366dac3f | postgres |
| propose_site_payment_terms | d4344f2a55ef71adc8593bec700d5b7a | postgres, authenticated |
| site_payment_pair | 6cc0486a06b5721b9abea0e97af9f0d4 | postgres |

共有の会社印 snapshot helper は会社印 ON/OFF を判定しない。新しい契約モジュール側で会社行を `FOR SHARE` 取得後、`company_seal_enabled` を確認する条件を保持する。送信・承認の両方がこの確認を通ること。

## 反映と反映後の確認

- 最新版の必要な検証が成功してから、公式 `apply_migration` で上記ファイルの SQL を反映する。`db reset`、一括 `db push`、既存履歴の `repair` は行わない。
- 実際に保存された migration version と source filename の対応を Issue #273 に記録する。違いを理由に過去履歴を改名しない。
- 新しい `private.site_contract_seals` と `private.site_contract_notification_outbox` の RLS と、anon/authenticated の直接アクセス拒否を確認する。
- 公開4 RPC は anon の実行不可、authenticated の実行可を確認する。ログインしていることだけでは利用許可にならず、内部の本人・会社 owner/admin・会社間連携・rollout・対象版の確認も必要。
- 未ログインの拒否を、実ユーザー・実対象を使わず確認する。実際の押印・承認・通知をテストデータとして本番へ書き込まない。
- 上記4つの既存関数の定義・ACLと、既存表の件数・内容 digest が変わっていないことを確認する。新表に実記録を作らない。
- security advisors を再確認する。新しい private deny-all 表による INFO と、権限拡大や新たな WARNING を区別する。
- 必要な場合は PostgREST の schema cache を更新する。RPC 未配備・権限拒否・タイムアウトを成功扱いにしない。
- 反映結果、最新 main、未完了項目を Issue #273 へ保存する。iPhone 導入と実機操作確認はそれぞれ別に記録する。

## 動作を守る条件

- 画面で確認した会社印の hash はサーバーから受け取る不透明な値として扱い、クライアントで再計算しない。
- 会社印・条件・対象版・本人が変わったら再確認する。会社印を OFF にする更新と競合した場合も押印しない。
- 送信結果が不明なら、無条件で再送せず保存済み記録を確認する。提案 ID・版・条件・操作者・操作種別・印影が一致した場合だけ成功表示する。
- 旧確認導線から新しい押印を偽装しない。明示的な RPC 未配備以外の失敗を、旧処理へ進む理由にしない。
- 確定済みの印影・操作者・時刻、既存の単価・請求書・署名は保持する。問題時は機能を無効のまま補修し、保存済み証跡を削除して戻さない。
