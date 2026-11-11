# OFF勤怠union × 有給給与 × 保存角印の管理操作回帰

基準main `a086828bb46819d74ca1bf9bd245e8f94a90dbdf`。既存union試験は給与履歴の整数ダミー、#824は有給scheduler/承認triggerと角印を組み合わせるが、GPS勤務日版 `force_manage_attendance` の有給→勤務→有給から実給与triggerが動く経路は確認していなかった。本試験はその経路に限定する。

実mainの管理/GPS勤務日、claim/proxy/meter/capability/source attach/meter attach/通知migration、新有給、角印style/3帳票snapshotを同じ隔離DBへ配置する。全会社gate行は作らずOFF。GPS capture契約は別担当の検証対象で本試験には配置しない。

合成設定日給12,000円・残業1,563円で実authenticated管理RPCを実行する。有給12,000円→2時間残業勤務15,126円→既存勤怠行を3時間へ更新16,689円→有給12,000円を確認。給与refreshを直接呼ばず、既存attendance/leave trigger経由で同期する。給与DLの前提schema・bank/metadata・invoice/合意生成patch anchorは既存isolated fixtures/stubであり、全請求書生成や全本番schemaの証明ではない。

勤務の実出退勤証拠2件、承認済有給との重複なし、再有給化による勤務証拠削除、manual/finalized/過去automatic給与の全row保持を確認。OFF union DDLだけでは全給与row不変。会社改名/書体変更後に同一明細への勤怠更新は保存印影を保持。ゼロ支給による明細削除を経て別IDで新規生成される明細は、その時の登録会社名を保存する（削除された明細の印影を推測復元しない）。gate/claim/通知/独立receiptは0を維持。

ローカルPGlite 0.3.14で成功。専用CIで独立PGliteと空のPostgreSQL17を検証する。PG17モードは既存fixture URL guardでローカル固定DBのみ許可し、既存業務tableがあるDBを拒否する。ローカルFlutter/実PG17は実行していない。CI成功・本番適用・実機操作は別。

実行:
`node tool/verify_attendance_paid_leave_seal_off.mjs <pglite-dist/index.js>`

実PG17:
`SKO_PAID_LEAVE_FIXTURE_URL=postgres://postgres:fixture-only-password@127.0.0.1:5432/sko_paid_leave_fixture node tool/verify_attendance_paid_leave_seal_off.mjs <pg/lib/index.js> --pg17`

本番接続・migration変更・Auth/RLSの本番変更・rollout ON・メール実送信はなし。参照Issue #273。
