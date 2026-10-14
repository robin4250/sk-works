# LINE一般非開放の実装準備

この変更は封印の準備であり、封印・本番適用・flag変更・配布を実行した記録ではない。新しい設定は `general_enabled=true` で現在の一般利用状態を維持する。既存LINE出勤表・請求書スイッチは変更しない。

## 境界

- `line_release_capability()` はversion 1とavailableのみを返す。取得失敗はクライアントで未許可として扱う。新設定の変更は独立した `set_line_general_release_enabled(boolean)` を、accountアクセスを維持するマスター本人だけが実行でき、監査行を残す。起動時やmigrationからsetterを呼ばない。
- 一般OFFでも有効なマスター本人はLINE専用操作を継続できる。既存の会社・グループ・参加者・請求権限へANDする追加条件であり、それらを拡大しない。既存 `can_access_communication_group` と認証基幹は変更しない。
- `chat_messages` のorigin=lineのSELECTとLINE binding/claim/auditには追加RESTRICTIVE policyを設ける。通常SKOメッセージ、既存permissive policy、受信済み行は保持する。通常SKOトーク自体を削除・停止しない。
- RLSを迂回する専用definerのdirectory/shared/linked/import/link/factoryと旧binding操作にも追加guardを入れる。一般OFF時は一覧は空、詳細・変更は拒否する。元の定義・ACL・owner・search_pathと13関数のbody hashを確認し、想定が違えばmigration全体をrollbackする。
- 通報・内容審査のdefiner経路もLINE本文・添付・本文snapshotの読取／操作をOFF一般から閉じる。元投稿が削除済みの通報は由来を証明できないため、OFF一般では非表示・操作拒否とし、行は保持する。通常SKOの元投稿が残る通報・審査は継続する。
- 送信は既存 `line_outbound_actor_allowed` へ追加する。enqueue、prepare、service-role claimが同じactor条件を再確認する。OFF前のticketでもOFF後のclaimは拒否する。OFF中に通常SKOへ投稿した本文を後で勝手にLINE送信するbackfillは設けない。
- service-roleの署名検証済みWebhook受信・保存・グループ観測と既存データは維持する。マスターは2024年1月からの月別表・履歴単価・請求書作成を継続する。

## 検証した範囲と残る条件

専用fixtureは実際の13関数定義を使用する。ロール／グループの基礎helperはfixture用であり、実会社・実ユーザーを作成・偽装しない。PGliteとPostgres 17用CIでdefault ON、一般各役割の直接SELECT、専用definer、master元scope、account restriction、既存queue ticketの再確認、通常SKO保持、OFF中の受信保存、ON復帰、元行・既存ACL/owner/search_path保持を確認する。別検証でbody drift時の全体rollbackを確認する。

これはSupabase Realtimeの実サービスへの接続検証ではない。SELECT policyは適用境界になるが、既に端末へ渡った本文の消去や、実Realtime配信はFlutter側のactor/capability変更時の消去・再読込と実機検証が別途必要である。

claim完了後からLINE外部HTTPまでの競争はDB transactionだけでは原子的に止められない。封印切替時はdispatch workerの送信直前再確認と、進行中送信を確認する手順が必要であり、このSQLだけで送信中の取消を保証しない。既にLINEへ届いた投稿を消す機能でもない。

Flutterのホーム／メニュー、LINE入口、共有メッセージ・最新プレビュー、通知・直接遷移が同じcapabilityでfail closedとなる変更と組み合わせ、完成した配布候補で検査するまでは一般非開放のblockerを解除しない。既存通知の作成・他者への送信、本番flag切替はこの準備で行わない。

2024年1月以降の実請求書を本人が取込・照合・確認する前にマスター整理を封印しない。封印がTestFlight前か後かは請求確認次第で決める。完成済みmainのiPhone Release上書きは本準備の完成待ちにしない。

## CLIと資料

新migrationはSupabase CLI 2.120.0の `migration new` で生成した。公式同版analytics資料で確認した `SUPABASE_TELEMETRY_DISABLED=1 DO_NOT_TRACK=1` を指定し、CLI分析送信を無効化した。

- [Supabase RLS](https://supabase.com/docs/guides/database/postgres/row-level-security)
- [Supabase Postgres Changes](https://supabase.com/docs/guides/realtime/postgres-changes)
- [CLI 2.120.0 analytics](https://github.com/supabase/cli/blob/v2.120.0/apps/cli/docs/analytics.md)
