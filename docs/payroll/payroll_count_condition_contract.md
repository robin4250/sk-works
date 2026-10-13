# 共通手当の回数basis（純粋Dart stage）

最新main ea9d80d、統合済み #843 ebaa458 を基準に追加。既存4basisは変更しない。
`PayrollCountCondition` は登録円整数単価×明示回数を計算する専用型。
時間・出勤日数へ回数を偽装しない。給与形態（時給／日給／月給）引数は無く、いずれにも同じ条件を使える。

数量は既存 `PayrollItemQuantity` の非負decimal文字列・4桁固定精度BigIntを再利用。
小数回数も技術的に保持できるが、業務上の半回許可・整数限定をこの型は決めない。
丸めは呼出元がdown/up/nearestHalfUpを明示指定。0回・0円は結果0で明細表示判断のみfalse。
負値・指数・曖昧入力・精度超過・安全整数上限超過を0へ変換せず拒否。
旧固定／直接入力の円額は変更しない。既存金額／名前から回数を推測しない。

DB・日報画面・settings・価格取得・会社権限・給与計算・確定snapshotには未接続。
永久UUID/source version/対象日価格/当時名称単位は後続adapterの責務。
同日複数現場の合算・日単位共有や過去日単価は推測しない。
総額と内訳は後続共通resolverの同じ結果を使い、旧名前一致加算との二重加算を防ぐ。

後続保存注意: mainのsave_daily_report_destination_draftはdaily_report_workersをdelete→reinsertする。
quantityを別RPCで後付けするだけでは旧client再保存で失われる。
省略は保存済みquantity保持、明示[]は解除として、保存／署名／修正projectionの同transactionへ接続する。
company→worker→対象月scope→settings→identityの順序を守り、manual/finalizedを再計算しない。

6境界testsを追加。ローカルFlutter SDKが無いため実行結果は最新headのFlutter/iOS CIで確認する。
このDraftは本番数量→給与連携の完成ではない。
