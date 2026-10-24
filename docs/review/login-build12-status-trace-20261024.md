# build 12 第一パスワードの設定状況表示

確認元: main `e8ca207ebd85043d1fce803d79584977d6abef5c`。実機報告: 第一パスワードのボタンは表示されたが、電話番号未登録と「設定状況は確認できません」を関連付けて認識した。

## コード上の事実

`panel_seven_page.dart` の第一パスワード欄には、アカウント状態に関係なく「設定状況は確認できません。Google / Appleとの連携だけでは設定済みと判断しません。」と固定文が出る。電話番号やprovider取得失敗から発生するエラーではない。

登録repositoryの `canSetPassword` は `(emailAvailable && emailConfirmed && email.isNotEmpty) || (phoneAvailable && phoneConfirmed && phone.isNotEmpty)`。確認済みメールとメールproviderが有効なら、電話番号未登録・電話provider OFFでも第一パスワード設定ボタンは利用できる。既存のrepository/card試験が、この組合せを既に検証している。

第一パスワードの有無はAuthの公開User情報から確定せず、OAuth identityや現在sessionのAMRからも推測しない。この候補ではstatus API新設、保存済みの偽表示、電話登録の強制、logout/signin、Auth/provider設定変更を行わない。

## 限定候補

第一パスワード欄の固定文を「登録の有無は取得できない」「未設定・登録失敗を示すものではない」「電話番号未登録でも利用可能な確認済みメールがあれば設定可能」と明確化する。

その後の実機報告で実際の保存成功が確認されたため、カードが `setPrimaryPassword` のサーバー更新・同一アカウント照合の正常終了を待った時だけ専用callbackを発行する。ページは当時の `PanelSevenSnapshot` に結び付け、現在のactor・検証済みログイン状態が一致する場合のみ「この画面で第一パスワードの保存を確認しました」と表示する。汎用 `onChanged`、電話・メール登録、保存失敗・キャンセルではこのreceiptを発行しない。

receiptは画面内の一時記録であり、Authの永続的password有無の判定ではない。ログアウト、session/actor変更、画面破棄で保持しない。対応する「？」ヘルプと関連UI試験を更新する。

保存・電話番号・メール・Auth repository・本人session・UID・Google/Face ID・第二パスワードの処理は変更しない。本人から保存済みの実機報告を受けているが、過去の保存をこの候補で遡ってreceipt化しない。この候補の配布後、同じ画面からの正常保存結果だけを表示する。実password認証のための本人ログアウト・再ログインは要求しない。

## 検証

- 元mainの該当固定文とOR条件を確認済み。
- 既存テスト `login_method_enrollment_repository_test.dart` は確認済メール/phone provider OFF時の `canSetPassword == true` を持つ。
- 既存テスト `login_method_enrollment_card_test.dart` は同条件で電話ボタン無効・第一パスワードボタン有効を持つ。
- 新UI試験は成功・失敗・キャンセル、電話/メール操作との区別、ページreceipt表示、session変更後の消去を対象とする。Flutter解析・関連UI試験は未実行。rootからの限定CI確認対象。
- 本番mutation、実SMS/メール送信、本人session操作なし。
