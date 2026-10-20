# 経費default-OFF runnerの独立レビュー候補

対象は `tool/security/expense_production_off_runtime/`。main機能PRとは別候補で保持する。

既存immutable4ファイルとexpense専用guardは無変更で再利用。private prepared/hash照合、実行前の固定fsync marker、単発BEGIN/COMMIT、結果不明時の再送拒否、READ ONLY再観測、既存prepareUnusedUndoによるactual metadata/OID付きprivate undo保存を、接続なしのreview harnessで準備した。

CLIは実行不可exit2。本番adapterは含めず、秘密取得・本番接続・SQL適用・gate変更・金額変換は0。PGlite実SQLとmock state machineの成功を本番可能と扱わない。未対応の接続adapter・native切断試験・exact private承認・marker解決運用を専用REVIEW.mdに列挙している。

追加のnative切断CI候補は、既存Expense default OFF preparation workflowの別job・専用空PG17 serviceに限定する。localhost固定guard/既存native fixtureを再利用し、COMMIT前backend切断→rollback、COMMIT後socket切断・親へのack未返却→installed、各fresh READ ONLY再観測と再送拒否を検査する。ローカルnative環境が無いためnativeテストは未実行・未合格。本番adapter追加ではない。
