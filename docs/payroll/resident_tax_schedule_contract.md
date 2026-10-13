# 個別住民税の月額・開始年月モデル

新規純粋Dartモデル `ResidentTaxSchedule`。会社料率に住民税を入れず、companyId / workerIdに固定された従業員別の手入力月額を扱う。制度の税率・年税額・分割額・徴収月は推測計算しない。

`ResidentTaxMonth` は年1〜9999、月1〜12の専用型で、他PRのRateMonth等へ依存しない。月額は非負円整数でVM/Web共通の安全上限9007199254740991まで。将来開始版を事前登録し、対象給与月以下の開始年月で最も新しい版を選ぶ。未登録、最初の開始月より前、適用中を別statusで返す。開始前はnullであり、明示登録された0円とは区別する。給与接続adapterはnullを0として扱うか未設定を確認するかを明示的に決める。

`register` は同じ開始月の重複を拒否する。既存版の変更は明示的な `amend` のみ。両方でexpectedVersion / actorId / changedAtが必須で、versionを増加し、before / after / actor / UTC日時を追記する。旧state、旧版履歴、現在timelineはimmutableで、未来版の登録順が前後しても選択結果は開始月順。開始月自体の移動/削除APIは用意しない。過去の登録月額を訂正しても既存確定給与のsnapshotには接続しない。

scopeはread/writeで一致を検証するが、これは値の取り違えを防ぐ契約だけでDB権限やactor本人性を証明しない。実保存adapterは認証済actor/サーバ時刻/versionの競合処理と会社所属権限を別途実装する。純粋モデルの時刻は呼出元提供のため監査の真正性を保証しない。

UI、DB、住民税開始月保存、給与への毎月自動反映は未接続。既存 `resident_tax_monthly` 固定額を開始月不明のまま勝手に履歴化しない。採用版の開始月/月額/条件versionは将来の給与snapshotへ値として保存する。

5testsは未登録/開始前/明示0、exact開始月/次版/年越し、将来版の事前登録、旧stateとbefore-after監査の保持、同月重複/競合/会社跨ぎ/従業員跨ぎ拒否、入力上限を確認。実行: `flutter test test/resident_tax_schedule_test.dart`。
