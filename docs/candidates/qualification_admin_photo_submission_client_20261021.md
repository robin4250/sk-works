# 管理者の保存済み資格写真：申請 transport 候補

基準: `8b7e335cff62d902c475eaa37365187c7adc9bfb`。製品画面・実 RPC・本番には未接続。既存 capability / readiness / prepare モデルは変更しない。既存の本人用 repository を管理者へそのまま流用せず、管理者用の固定 scope と永続化契約を独立ファイルに置く。

## 再利用する契約

既存 `personal_qualification_submission` の `prepare_admin_saved_photos`、`get_photos`、`submit`、`cancel_photos` のみを注入 callback から呼ぶ。prepare は既存 pure command と ordered baseline CAS 契約を使う。新 API、アップロード、Storage 削除、資格本体削除、承認 list/review は追加しない。空選択は保存済み写真をすべて除外する申請である。

応答は実在する9項目 `version/id/target_id/requested_by/status/cancelled/reason/photo_paths/upload_paths` を厳密照合する。会社・worker を応答に捏造しない。version、固定 request、対象資格、actor、選択順序、空 upload_paths、状態と取消の整合を検証し、未知キーも拒否する。確認済み状態から draft への退行は変更操作前に拒否する。

## 操作と復旧

| 操作 | 契約 |
| --- | --- |
| prepare | 会社・actor・対象・baseline・固定 request を先に永続化し、CAS と再読込が一致してから prepare → get |
| submit | 明示操作のみ。先に get、draft の場合に intent を永続化して submit → get。既 pending/approved は再送しない |
| cancelDraft | 明示操作のみ。get で draft の場合だけ intent 永続化 → cancel → get |
| recover | 同一 request のみ。prepare_unknown は同一 prepare を再実行可能。それ以外は get のみで submit/cancel は再送しない |
| acknowledge | 明示確認後、get が非 draft の場合だけローカル receipt を CAS 削除し再読込。サーバーは変更しない |

RPC の通信結果不明時は同一 ID の get だけで照合する。構造不正な成功応答を通信失敗へ読み替えて迂回しない。未確定結果と receipt は保持し、新 ID を自動生成しない。

ローカル記録は厳密な10キーの JSON。actor/company 単位の1件を占有し、target 不一致は拒否する。各 phase に revision を増やし、同じ phase の並行操作でも CAS で1件だけが進む。Store 書込の失敗・応答消失・再読込不一致時は mutation RPC を送らない。scope の変更・背景化・購読切断・認可喪失は sticky に失効し、元へ戻っても復活しない。

## 検証と残条件

`tool/verify_qualification_admin_photo_submission.dart` はネットワークなしの fake Store/RPC/scope で425 assertions 成功。固定ID、prepare/submit/cancel通信結果不明、再起動、状態退行、厳密応答、不正ローカル記録、CAS競合、readback不一致、actor/company/target/背景化/ABA失効、default OFF を含む。assertion 数はテストケース数ではない。package import と stdout を使い、新ファイルの if は braces を付けた。Dart format 済み。ローカル Flutter analyze/test は実行していない。

独立読取レビューでは候補単体の blocker は見つからなかった。実接続には次が必要:

- 複数 repository/プロセス間で原子的かつ耐久的な Store adapter の実装と検証。メモリ Store は検証 fixture のみ。
- 実 RPC adapter の認証 token と scope を固定し、遅延応答時も会社・actor・対象の切替を取り違えない検証。
- 別 target で pending を検出した際、元の対象へ戻れる製品導線。別 request を作って回避しない。
- 未証明の複数所属承認 list/review の確認。既本人 repository や他の対象への迂回はしない。
- 対象ファイルの CI 解析・repository 検証と、その後の正規画面接続・承認経路・実機確認。

この候補は書類削除の実機完了を意味しない。本番適用・送信・製品 route 接続は行っていない。
