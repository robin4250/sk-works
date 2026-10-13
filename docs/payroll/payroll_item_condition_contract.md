# 支給・会社独自控除の独立条件モデル

`lib/features/payroll/domain/payroll_item_condition.dart` は新規の純粋Dartモデル。UI、DB、既存給与計算器、給与確定snapshotへ未接続であり、現在の支給/控除金額を変えない。

| basis | 条件 | quantity |
| --- | --- | --- |
| hours | 時間 × 円整数単価 | 必須 |
| attendanceDays | 出勤日数 × 円整数単価 | 必須 |
| monthlyFixed | 登録月額固定 | 受け付けない |
| directAmount | 直接入力円整数 | 受け付けない |

給与形態（時給/日給/月給）を引数やswitchに使わない。すべてのbasisを支給と会社独自控除に使用できる。所得税・住民税・社会保険の制度計算には使用せず、別契約から採用された結果と分離する。

quantityは小数点以下4桁までの非負decimal文字列を厳密にparseし、BigIntの整数/10000として保存。二進浮動小数点経由で丸めない。4桁はこの新モデルの技術的入力契約であり、既存実績を無断で4桁へ丸める方針ではない。接続adapterは精度超過を拒否/解決する必要がある。

単価/固定/直接金額は非負円整数。quantityのscaled値と計算済み円はDart VM/Web共通で正確な整数上限9007199254740991を超えれば拒否する。負数、NaN/Infinity、指数、空欄、曖昧な入力、精度超過は0へ変換せず拒否。固定/直接basisへのquantityは意味のない引数として拒否する。

丸めは呼出元が `down` / `up` / `nearestHalfUp` を必ず選択する。法的な全体基準や制度の標準値をこのモデルで決めない。qty×unitの一項目に丸めを適用し、制度全体の集計/標準報酬/源泉徴収等の丸めとは混同しない。`legacyDirect` は既存name/amount_yen追加項目のamountを直接入力basisへ引き継ぐための入口で、ラベル/権限/serializationは既存側の責務。直接入力を自動的に時間式へ推測変換しない。

結果0円は `shouldDisplayOnStatement=false`。これは給与明細の表示判断だけで、設定項目や履歴を削除する指示ではない。

`PayrollFamilyCount` は対象判定済み人数をadapterから受け取り、auto/manual/resetだけを保持する。手動0人は有効なoverride。登録対象人数の更新後もmanual値を保持し、「自動に戻す」で最新automaticCountを採用する。資格条件・登録家族の取得・税扶養判定・人数単価の制度は未実装。将来adapterが対象0人を提供した場合の給与支給は0円として別の計算接続で扱う。

新しい6testsはdecimal精度と半円境界、basis独立、固定/直接入力互換、必須quantity、入力拒否/overflow、0円非表示、家族0override維持とresetを確認する。Flutter SDKがある環境で `flutter test test/payroll_item_condition_test.dart` を実行する。
