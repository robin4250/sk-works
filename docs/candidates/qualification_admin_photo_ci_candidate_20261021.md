# 資格写真候補だけのCI検証ブランチ

基準main: `d70b90b9f19f854e8f13c00c4a1e66fbfeb4235e`。
専用branch: `fix/qualification-photo-baseline-readiness-ci-20261021`。
PR1309へ追加せず、資格候補だけを別draft PRで検証する準備。ローカル作成のみで、GitHub送信・PR作成・CI dispatchはしていない。

## 移した既候補

- `97c57e6e` → `c289572e`：表示済み写真baseline CAS補修・隔離検証。
- `6a9f1f96` → `139016b1`：原support client `70a0378f` の内容無変更再利用。
- `1859338c` → `433a0f2d`：既draft値型を使うpure prepare payload。
- `3b9d3bb8` → `ef1c7a00`：pure toolのpackage import/stdout lint追補。
- `9617578a` → `409762d8`：後方互換の専用readiness契約と未導入OFF。

Cの注文書設定/角印レイアウト、Dの給与、Fの招待、PR1309固有の追加差分を含めない。変更先を資格固有lib/test/tool/docsと既存資格workflowのallowlistで検査した。

## 既workflowへの接続

新workflowを作らず `.github/workflows/qualification-admin-photo-postgres-race.yml` を拡張。

- 既 `native-lock-order` jobは内容を保持。既管理写真candidateのPostgreSQL17 lock-order検証であり、新baseline/readinessのnative保証に読み替えない。
- `baseline-readiness-sql` jobは固定fixture lockをnpm ciで解決し、PGliteの2構成でbaseline→readinessを連続検証する。readiness verifierが既baseline verifierと原fixtureを再利用するため、同じbaseline検査を別stepで二重実行しない。
- `client-contract` jobは既設定のFlutter3.47.5・stable・cacheと固定pubspec.lockを使う。未接続client6lib、2pure tool、対象repository/parser test2filesをanalyzeし、pure31+29項目と非widgetのrepository/parser testを実行する。
- 未実行だったreadiness repository4tests（既定OFF、専用action/旧応答/例外でfallbackなし、late actor ABA、dispose）を対象testfileから実行する。既draft-page widget testはこの専用jobでは実行しない。
- PR/push両方のpath filterに新client/test/tool/SQL候補を追加し、既pathを維持する。新secrets、production URL、本番接続は不要。

## ローカルで確認した結果

- 新worktreeからPGlite2構成のbaseline/readiness・既権限/互換/metadata検査が成功。
- 一時package configのsk_works rootUriだけをこのworktreeへ変え、Flutterを起動せずpure payload31項目＋readiness29項目が成功。
- YAML構文・job集合・PR/pushの重複pathなし・全lib/test/tool参照の存在、node構文・git diff-checkが成功。
- ローカルFlutter analyze/test、native PG再実行、本番操作、送信は行っていない。repository4testsの遠隔成功は、これから別draft PRで確認する事項。

CI成功前に本番・製品導線・送信処理の完成とは扱わない。prepare/submit/応答照合・不明commit復旧・実機削除確認、本番の原本保護/native/既存保守影響などの未完条件は各元候補の文書どおり保持する。
