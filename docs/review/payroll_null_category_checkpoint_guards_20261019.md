# NULL給与カテゴリー：コード差替え用checkpoint生成

`tool/payroll_null_category_checkpoint.py` は非公開で採取された単一関数のcheckpointと給与trigger checkpointを入力にし、`guarded_forward.sql.review-only`、`guarded_restore.sql.review-only`、匿名`public_manifest.json`を生成する。SQLの実行・接続・再計算機能はない。出力は新規のGit外ディレクトリ700、ファイル600。private入力・生成SQLは公開repoへ保存しない。

対象は `private.refresh_automatic_payroll_internal(uuid,uuid,date)` の `category:=a.work_category;` 一箇所を `category:=coalesce(a.work_category,'day');` とするコード変更のみ。指定済み元body MD5、入力definition SHA256、owner-only ACL・空search_path・security definerを検査する。前後のSQLguardは完全definition、OID、signature、owner、ACL(NULL区別)、config、security/volatility/parallel/strict/leakproof、言語・戻り型と、`payroll_statements`非内部trigger全件のOID・enabled・完全定義・関数body hashを比較する。旧manual linker checkpointの前後guard方式を再利用し、別対象SQLや古い給与定義を転用しない。

各artifactはtransactionと短いlock/statement timeoutを持つ。guard不一致で停止し、未知の後続変更を上書きしない。CREATE OR REPLACE一件以外のDDL、ACL/RLS/Auth/role/trigger変更は含まない。定義差替え自体は給与データ更新ではなく、既存明細を再計算しない。restoreは**コードだけ**を戻すもので、後から正規保存された給与行・audit・通知を戻すものではない。既存明細refreshは別のデータ更新として対象・before保護・副作用・承認条件を示す。欠落勤怠の強制作成・署名捏造・保険仮値登録は対象外。

## 再利用可能な合成検証

`tool/verify_payroll_null_checkpoint_guards.mjs` は既 `setupPayrollScopeFixture` と保存済みmigrationを読み、合成PGliteから採取した入力だけで生成する。forwardの最小一箇所差分、restoreの完全一致、旧状態での重複restore拒否、未知後続bodyのrestore拒否、trigger enabled変更時のforward拒否を確認する。fixture本人の権限だけで実行し、本番checkpointをテストへ渡さない。実行例：

```sh
node tool/verify_payroll_null_checkpoint_guards.mjs /absolute/path/to/pglite/dist/index.js
```

これは生成guardと原典互換の合成検査であり、現在本番との一致やnative PG17のDDL並行実行を証明しない。実適用前にはrootが新鮮なcheckpoint・対象metadata・原典artifact hashを照合し、明示承認を満たす。guardとDDL間の任意の競合DDLを完全に直列化するものではないため、同対象の並行deployを止めた運用窓が必要。適用後にも同metadataを独立読取する。本番権限変更を含まない今回に全面Auth/Storage archive復元を機械的に追加要求しないが、既存の本番HOLDを解除する文書ではない。

## checkpoint表示形式とevent triggerの追加guard

rootレビューで、実checkpoint採取は `pg_get_triggerdef(oid,true)` なのに初版guard/fixtureは既定falseを使用する不一致が判明。v2は採取・guardともtrueへ統一した。回帰では合成triggerのtrue/false出力が実際に異なることをassertし、false入力のforwardが拒否されることを確認する。初版private出力は保護し、修正版は別ディレクトリへ生成する。

`--event-triggers /private/event_triggers_checkpoint.json` を指定すると、全event triggerのname/event/enabled/function schema/name/source MD5を適用前後に比較する。指定しなければmanifestは未検査を明示する。空配列も有効な観測済みbaselineであり、空baselineへ新規event triggerが追加された場合の拒否を合成試験で確認する。snapshotにないevent owner/OID/tags/関数ACL/config等まで確認済みとは扱わない。guardを追加しても実event triggerを無効化・変更しない。既schema-cache reload等の副作用は別レビューの対象で、guard成功は本番変更承認ではない。
