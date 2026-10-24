# 退勤の時間手当：明示時間と二署名の接続候補

これはreview-onlyの独立候補。本番更新と共有DailyReportPageへのUI組込は行っていない。公開APIはreview-only候補である。既存のclosed-day scope readerを再利用し、人工×8・生の経過時間・月別manual数量から勤務時間を推定しない。

## 実装した契約

- 最終退勤に結び付く日報で、当日の休憩を除いた実勤務時間を明示入力する。空欄nullは未入力、明示0は有効。0〜24、小数4桁以内を検証する。金額や給与の時給そのものは変えない。
- serverの全勤務集合fingerprintとexpected revisionを照合し、本人または既存の勤怠管理権限でのみdraftを保存する。
- 時間変更で両署名を解除し、同じ時間・scopeの再保存は署名を維持する。
- 最終日報に時間手当の選択がなくても、二署名を持つ最終日報の時間を独立したprivate ledgerへ保存する。価格receiptを更新しない。
- 正式なattendance entry、現日報のcanonical両署名、現在の全勤務集合、最新input revisionがすべて一致するledgerだけを一意に解決する。
- 既存aggregateの重複日・価格衝突・異なる登録単価・日単位計算を保ち、hourのnull分岐だけへ署名時間を供給する。内訳にledger ID/report/scope fingerprintを残す。
- 新勤務・退勤・証跡の更新/削除は署名writerと同じworker/month lockを使う。既存ledgerのある日の証跡変更は正規の未確定給与再計算を要求する。既確定帳票を直接変更しない。

source producerは実際に観測したreport_basis/sign_daily_report/aggregate/resolveのbody hashを固定する。署名writerの既存scope lock・会社/社員権限・正式勤怠・日給計算・会社手当receipt処理を保持する。既存関数を別名へrenameして古い呼出を残す方式は使わない。

## 検証範囲

新しいNative wrapperは、既存closed-day proofを変更せず拡張する。実clock guard、実worker/month lock、実aggregate bodyを使用する。membership・署名保存行・attendance投影・payroll refresh spyは明示した合成fixtureであり、本物のGoTrueや完全な給与保存の検証とは扱わない。

検証対象は未入力/不正時間/旧revision/旧scope拒否、同値保存、片署名拒否、二署名の一度だけcapture、正式勤怠前の保留、7.25時間×200円=1450円、同日複数receipt一度のみ、日単位500円不変、価格receipt不変、価格衝突保留、明示0と不明null、署名とのnew-clock競合、変更で署名解除、後続証跡でquantity失効と再計算要求。

前段階root head `0efa9d55e279607fd0fa4965c005fba6cf9a79dd` でprivate ledger Native75項目と、既存保存/署名/正式勤怠/給与のsource chain140項目が成功した。後者は実1000円単価×7.25時間=7250円、支給27250円、保存差引一致、再出勤で保留へ戻ることを確認した。GoTrue/税の周辺は明示した合成/neutral fixtureである。

その後、独立reviewに基づきclock UPDATEのOLD/NEW双方のscope lock/刷新を追加した。新しい公開API/Flutter/PDFテストと合わせてremote再検証が必要。localではNode構文、producer生成、YAML構文だけを確認し、Flutterはremote CIに限定する。

## Release前の残る接続

- 公開read/save RPC候補は既存registrationのlive-session helperを再利用する。新たな本人IDや認証方式は作らない。Nativeでlive session型契約・他worker/別sub/anonymous/削除session/anon/service role拒否を検証する。実GoTrue/PostgRESTは別途未検証。
- standalone card/repository/section、入力/異常scope/0-null/session ABA/遅延応答のFlutter検証を追加した。共有DailyReportPageは変更せず、root用の最小hookを `checkout-paid-hours-page-hook.md` に記した。
- 既存の実sign→formal entry→給与保存計算は前段Native成功。今回、その保存JSONを現在のmapper/PDFへ渡し文字/金額/はみ出しを確認する専用jobを追加した。
- readerの物理証跡更新による失効条件、過去route互換、正規訂正と再署名の実確認。
- production source再照合、bounded install/unused restore、rollout、管理者実機確認。

これらを終える前に時間手当が給料明細へ反映済みとは報告しない。
