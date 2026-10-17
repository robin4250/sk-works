# 運転免許証upload pilot：本番適用記録 2026-10-09

Issue #273。操作担当rootからの実行報告を保存する。検証担当は本番接続・DDL・DMLを実施していない。基準main d7dcd723、source PR #834 head 7e4b5f089a2265c2458304c8af8d12c2cfa90d43。source PR全5CI SUCCESS後、rootがexpected headを確認してmain 6e9e1b25a95bd1289d52992c6d323ac4a1a0e4a8へ統合した。統合後main push CIは別確認。

## 適用sourceと追加境界の修正

source migrationは `20261009111338_license_document_upload_pilot_contract.sql`。root549e656のexact SQL SHA256は `3187f1f5c35e68009a5e7577ab097f6faf6e778f1f3501a2d1409babbba2da62`。本番ledgerは `20261009114722 license_document_upload_pilot_contract` としてrootが記録した。source時刻と実適用ledger時刻を区別する。

旧root9777f99ではPUBLIC INSERT pauseからanon権限のない新helperがplanされ、既存非official bucketのanon許可が拒否へ変化した。隔離fixtureで再現して旧head44483bd8の統合を止めた。root549e656はPUBLICの旧bucket条件とauthenticated専用RESTRICTIVE INSERT例外policyへ役割を分離し、anon新helper EXECUTE拒否を保った。

新sourceは専用CI37925157726/job113802210231でPGliteと実PostgreSQL17とも18前提不一致rollback、55本人/会社/path/保持/ACL、4旧非official anon/auth許可・拒否before/afterケース成功。旧row/trigger/guard/helper/worker列ACL不変と同一source SHAをログ確認した。

## 本番操作の結果（JST）

| 時刻 | 操作 | 結果 |
| --- | --- | --- |
| 初回試行 | 適用前snapshot照合 | workers1行の外部更新（phone/department/hire_date/updated_at）を検出し、DDL前にROLLBACK。既存データを上書きしなかった。 |
| 20:46:33 | 最新snapshot再取得・非公開保存 | 更新後の実データを新しい基準として保存。生データ、保存ID、対象UUID、基準データhashをgitへ保存しない。 |
| 20:47:22 | rootによるschema適用 | SHARE lock内で既存6表全row、helper、ACL/RLS、9trigger、92列ACL、public policy、対象Storage不変を確認。pilotは0件でOFF。 |
| schema適用後 | 別のguarded DML | 運転免許証の会社/要件1組だけをON。schema適用と対象ONを別操作として扱った。 |
| 20:49 | read-only本人role確認 | account許可=true、対象license path許可=true、他要件許可0、見えるenabled pilot1。status2/history4/objects0不変。 |

公開資料には対象の識別子、個人情報、DML原文、バックアップ生JSONを含めない。

## 保持された境界

新helperはSECURITY INVOKER、anon EXECUTE拒否。pilotのclient INSERT/UPDATE/DELETEはいずれも拒否。既存4guard、保持履歴のUPDATE/DELETE拒否、他official2bucketの停止を維持。Auth、会社role、Master権限の付与はない。同一要件でも名前snapshot不一致は停止し、他書類の自動許可へ広げない。

advisorsは観測時刻を除外した意味的finding集合（58/2/155/1）が適用前後で不変とのroot報告。新しい全体セキュリティ完成の証拠ではない。

## 完了と未確認

完了：限定schema適用、対象1組だけON、保持・権限境界の本番read-only確認、exact sourceのPGlite/PG17回帰。Secret37925157944、attendance union37925157812、代理退勤SQL37925157785もSUCCESS。

Flutter37925157901もテスト・PDF artifact・pre-device gate・Android APKまでSUCCESS。

未確認：統合後main push CI、実Storage HTTP/upload、実iPhoneでの免許証添付操作と最新Release導入、署名・TestFlight。DB policy判定trueをHTTP403解消済みや実機操作成功として扱わない。外部メールも実送信済みではない。
