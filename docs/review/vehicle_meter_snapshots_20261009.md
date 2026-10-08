# 運転手のメーターsnapshot・減少値の最小実装

前提PR #761（車両claim、初期OFF）に積み重ねた変更。本番未適用。現行アプリへの画面接続、日報PDF表示、整備間隔、選択管理者1〜3人、通知dispatcher、外部メールは未実装。

## 保存

新規claimのINSERT時に車両現在値とサーバーのclaim作成時刻をsnapshot。既存claimにはNULLを維持し、推測補完しない。

新RPC `record_vehicle_driver_meter(source_clock_in_id, event_id, current_km, manual_distance_km)` は退勤後の運転手本人だけが利用できる。日報を他メンバーが入力しても、運転手のメーターはこの独立RPCから登録する。

1. 現在の会社所属・active worker・account guard・有効なrollout・claimの所有を検証。
2. claim/rollout/車両をロックし、別利用や管理者の基準値変更がないことを検証。
3. 前回／今回／当日距離／勤務日／入力者をimmutable eventとして記録し、車両現在値を同じトランザクションで更新。
4. 今回値が減る場合は、その日の走行距離の手入力が必要。負の差分から距離を推測しない。前回値を保持し、今回値を新しい車両基準にする。
5. 減少eventにつき一つだけ、管理者向け警告をprivate outboxへ保存。dispatcher未接続なので「管理者へ送信済み」と表示してはいけない。

数値は非負・有限・小数1桁。読取値を黙って丸めない。通常時の任意距離上書きは許可しない。

同じevent ID・同じ値の再送は、登録済みsnapshotを返す。車両の現在値を読み直して0kmになったり、後続勤務の値を巻き戻したりしない。新しいIDや別の値による同じ勤務の再登録は拒否し、承認修正へ誘導する。訂正RPC自体は別対象。

後続運転手のclaimが既にできている場合、最初のメーター保存は拒否する。現在値がまだ同じでも、古い勤務の距離を後続勤務へ混入させない。最終的なUI接続では退勤・最終メーターの同一transaction化が望ましい。退勤時に未登録で進んだケースの後登録・訂正は、別の明示的な処理を完成させるまでONにしない。

## 互換性

既存`save_daily_report_vehicle_usage`のpublic signatureとACLはそのまま。導入時点のprivate実装をrestricted legacy関数へ保存し、OFFでは従来処理へ委譲する。

ONでは旧RPCの車両値書込を拒否する。これによりグループ日報入力者が運転手の値を更新する抜け道を防ぐが、既存`saveDraft`はworkerごとに旧RPCを呼ぶため、**画面・日報保存の移行前にONにしてはいけない**。

eventのsource/worker/vehicle UUIDは履歴snapshotとして保持し、attendance/claim削除のCASCADE対象にしない。元勤務の承認修正で削除されてもmeter eventは消さない。company削除は既存の会社単位の処理に従う。アーカイブ処理全体の対応は別検証。

## 検証

PGliteで実既存vehicle RPC、既存GPS勤務日migration、claim migration、新meter RPCとRLSを実行しPASS。既存OFF RPC互換、ON旧RPC拒否、運転手限定、管理者代入力拒否、月跨ぎsnapshot、減少時手入力、新基準、同値再送、警告一件、古い日報再保存、後続claim後の遅延保存拒否、direct UPDATE拒否、private関数/anon非公開、blocked account、NaN/精度拒否を検証。

実Postgres二接続競合、実機、OCR精度、日報PDF、通知配送、選択管理者1〜3人、メール、整備繰返しは未検証または未実装。完了扱いにしない。
