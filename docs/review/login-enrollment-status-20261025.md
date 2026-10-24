# ログイン登録状況の独立修正候補

基準 main `22ecb36d0b15bc0fb498f3c23016508507ea5a99`。GitHubから取得した enrollment card/test は `999b06cf4a36bc63b15fb5b200f7ad7186c18786` の同ファイルと全文一致。snapshot基準commit `82be504` はこの2ファイルだけを保存した原典であり、完全なmain履歴ではない。Issue #273本文・最新コメントを2026-10-24 UTCに読み取り確認。給与3点と別laneで、次Releaseの待機条件にしない。

## 修正

登録方法の再読み込み失敗時、旧stateが残って旧provider/電話登録ボタンが再表示される問題を解消する。再確認中は旧stateを外し、取得失敗は未登録やprovider無効と断定しない。再読込成功後だけその最新の状態を表示する。既存generationチェックを保持し、遅い旧responseは最新結果を上書きしない。

電話番号の未登録・登録確認未完了・SMSコード確認待ち・登録確認済みを区別する。provider準備中は別の表示で、SMS送信やprovider有効だけでは登録済みにしない。詳細は初期折り畳みの「？ 登録状況の見方」へまとめる。

取得失敗と操作結果のmessageを分離し、第一パスワード更新・同一アカウント検証が完了したreceiptは、その後の設定取得失敗で取り消さない。逆に失敗した読取/電話/メール処理でpassword receiptを発行しない。`onPrimaryPasswordSaved`、ページ側のactor/snapshot-bound receipt消去契約は変更しない。

repositoryの同一actor/token確認、認証eventによる失効、会社所属照合、nonce要求、Google/Face ID・第二パスワードの処理は変更しない。UI単体で別actor判定を新設せず、ページ側の本人state切替とrepositoryの既存拒否を維持する。新UID、ログアウト、SMS/メール送信、Auth設定変更、本番読取/変更は行っていない。

## Appleの残り

既存独立調査 `5ad866a`/`3aa5968` は現行 source と整合する。`AppleAccountLink.begin` は同じサーバー検証済みtokenの直近300秒OAuth AMR、Google identity、所属、provider設定を確認する。長期維持中の本人Google sessionを保持してこのAMRを更新する再認証接続は未実装。通常Googleログインを設定画面から起動する方法はsession置換の危険があり採用しない。password proofでOAuth要件を置換したりAMR条件を削除しない。

Apple providerの既存boolチェックは読取失敗と設定OFFを同じfalseへ畳む。実提供状態を三値で示すには既存source/card契約と専用fixtureを別途変更する必要があり、この3path候補では扱わない。本番provider有効状態・Apple実本人連携・single-session設定・独立PKCE/challenge固定は未確認。Apple UIの汎用失敗文に残る「直近ログイン」誘導も、同session再認証の安全な契約がない以上、機能完成とは扱わない。

## 検証

追加widget回帰候補は、未登録とprovider無効の区別、未確認番号、取得失敗で旧ボタン非表示→再取得回復、遅い旧response拒否、初回取得不明、password保存成功後の読取失敗でもreceipt維持を検査する。既存保存成功/失敗/取消、電話・メールとreceiptの分離試験を保持。

`git diff --check` 成功。ローカルFlutter実行禁止に従い、analyze/widget testsは未実行。rootの独立remote CIで enrollment card/repository、panel-seven state/receipt関連の既存試験を合わせて検証してから統合判断する。実機/本番Auth確認の完了ではない。

公式資料はSupabase search_docsで既存identity linking/updateUser確認手順を参照した。新Supabase API・DB schema・provider接続を追加していない。
