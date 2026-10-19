# 友達操作の本人切替境界

基準main2896d847。友達検索結果、申請/承認/拒否/削除の確認画面は、画面の本人epochを保存して既存watchActorChangesと照合する。本人が変わって元に戻るABAでも再利用しない。stream errorでも一覧/検索結果/ピンを破棄し、開き直すまで旧画面を再有効化しない。

既ChatActorGuardで確認dialogと追加方法sheetを無効化し、確認後・既RPC呼出直前・応答後にも本人/epochを確認する。dialogを開く前からbusyにして同時確認を防ぐ。戻る/キャンセルはbusyを解放する。遅い検索成功/失敗や送信後結果は別本人の表示・再読込へ反映しない。ピンの端末保存にもepoch確認を追加する。既プロフィールguard・権限・RPC名/引数・友達承認/紹介フローは保持。

実画面の合成repositoryで遅延検索成功/失敗、4操作の確認中ABA、同時callbackと取消後再操作、送信後ABAの古いreload拒否、招待sheet取消、actor stream errorを検証する。既chat-display workflowへ追加し、ローカルFlutter実行不在のためCIで解析/実行を確認する。

serverへ送信済みの操作を取り消す保証、token失効・実server/RLS・全chat操作・実電話招待の送信を証明する変更ではない。初回QR/紹介完了帰属/ポイント・通知の既未完を完了へ戻さない。本番/Auth/DB/権限変更なし。
