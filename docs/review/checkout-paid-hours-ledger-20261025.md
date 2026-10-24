# 退勤の時間手当：明示時間と二署名の接続候補

これはreview-onlyの独立候補。本番更新・公開RPC・UI接続は行っていない。既存のclosed-day scope readerを再利用し、人工×8・生の経過時間・月別manual数量から勤務時間を推定しない。

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

**remote Nativeはこれから実行する。** localではNode構文とproducer生成のみを確認した。

## Release前の残る接続

- 公開RPCと既存session/account/attendance権限の実GoTrue/PostgREST検証。
- DailyReportPageの明示時間入力と保存/再読込。現在の強制日報UI担当と同じfileを並走編集しない。
- 既存の実sign→formal entry→給与保存計算→PDFまでを新ledgerと組み合わせたsource-bound flow proof。
- readerの物理証跡更新による失効条件、過去route互換、正規訂正と再署名の実確認。
- production source再照合、bounded install/unused restore、rollout、管理者実機確認。

これらを終える前に時間手当が給料明細へ反映済みとは報告しない。
