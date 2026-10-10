# 会社共通手当の独立管理UI（限定stage）

DB契約は #860 latest60c754b7を継承し、bounded history追加と独立page/repository/helper/testsだけを接続。settings_pageへowner/adminかつ明示会社IDがある場合だけ「会社共通手当」入口を追加。既存VAT/料率/所得税入口・会社rateページ・給与・日報は保持する。本番未適用、main未統合、数量/給与連携未実装で製品完成ではない。

admin readで会社ID・契約版・明示整数version・全3slot・現役永久IDを検証。未採用の会社は登録済み名称/単価/単位全3枠を表示し、明示確認した原値だけ採用する。改名・編集は同ID、廃止は名称を明示解除（既存単価と単位は保持）、廃止後の登録は新ID。保存/廃止前に変更後の全3枠を再確認する。履歴は折畳み、最初100件とcursorによる過去50件取得、DB履歴は削除しない。

保存journalは料率とは別型/別 `company-allowance-identity-pending-v1` namespace。actor/companyからhashedファイルkeyを作り、application support内でnativefilelockと同keymutexを保持する。RPC前にtemporary fileを書いてflush成功→atomic rename成功を確認。既存unknown recordを上書きしない。temporaryだけ残る場合は型/actor/company検証後に復元、正本とtemporaryの両存在/破損は拒否、CASで対象recordが同一の時だけclearする。SharedPreferencesは使用しない。

送信結果不明/通信失敗/応答FormatExceptionではjournalを保持し、画面を閉じても再起動しても再送しない。版expected+1・同actor・同event・全3枠の要求値・継続すべき永久IDが保存履歴と完全一致した時だけ解除する。現在値が後から変わっていても送信時の履歴で照合する。最新100件から外れたjournalもexpected+2のcursorから1件だけ取得して検証する。失敗/不一致は編集停止を保持。SQLの明示拒否（40001/22023/42501）だけrecordをCAS解除し、最新readから再確認する。自動再送無し。

旧DBは対象admin read RPCのmissing PGRST202/42883だけ「準備中」。認可/通信/別RPC欠落はエラーで、旧設定値をこのpageから勝手に保存しない。actor変更はbound actor照合で停止。従業員向けlabels/日報数量/給与連動はこのUIの対象外。

会社設定入口から選択会社IDを渡し、実navigation widget fixtureで選択会社/閲覧者非表示/空会社非表示を検証する。既存会社rate editorは保持する。新ページはowner/admin RPCの読取成功が前提で、viewer/一般にはDBがadmin readを拒否する。正式導入には全schema replay/実JWT/端末/後続quantity/給与snapshot保持が必要。
