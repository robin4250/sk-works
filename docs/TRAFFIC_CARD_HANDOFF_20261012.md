# 交通カード（2026-10-12）

確定仕様：ホーム天気の直下、LINEトークの上。横一列4枠を保持し、最寄駅・電車乗換・バス停の3入口、4枠目は空欄。既存SKOテーマ色を使用。アイコンは変更可能な建物・電車・バス。最寄駅/バス停はGoogleマップ、電車乗換はYahoo!乗換案内。SKOのGPS権限・位置情報取得・住所/ユーザーID送信は追加しない。検索/現在地は外部サービス側で操作する。

## 実装契約

`TrafficHomeCard(availability: TrafficAvailability(...))` を共有ホームへ渡す。表示位置は天気とLINEの間。ロード済み `MasterFeatureAvailability` の `trafficNearestStation` / `trafficTrainTransfer` / `trafficBusStop` を渡す。初期値・旧RPCの欠損キー・失敗時はすべてOFF。地域住所をこのカードへ渡す必要はない。起動先は固定HTTPS allowlist、外部アプリモード、連打防止と失敗時の再試行表示。`launcher` はテスト用注入。非表示/並べ替えは共有ホーム担当と接続する。

マスター設定は既存の `private.master_feature_settings` / `current_master_feature_flags` / `set_master_feature_enabled` を拡張。新3キー `traffic_nearest_station` / `traffic_train_transfer` / `traffic_bus_stop` は初期OFF。既存車両/ルート値・更新履歴・マスター判定関数・ACL/RLSを保持。新規追加migrationのみ。以前の適用済みmigrationは変更しない。マスター画面に3項目を追加。一般社員/会社管理者に切替権限は追加しない。

## 検証/未接続

ローカルPGliteで本物のSQLを実行し、既存2キー値/更新者/更新日時不変、3キーON/OFF、一般ユーザー拒否・匿名拒否・private直接参照拒否・無効キー拒否・RLSとマスター判定body保持を確認。Flutterはローカル未実行、CIで320px文字1.6倍・4枠・3リンク・OFF・連打・失敗・ヘルプを検証する。

天気担当の共有ファイル解放後、天気→交通→要対応へホーム接続、メニュー表示ON/OFFと持ち手並べ替え、英語辞書と？ヘルプを追加。LINE独立カードは現在未実装なので、将来交通の直下へ追加する。master flagsは既存の出勤状態読取フロー内で同じactor/generation照合を再利用して読み取り、失敗時は交通だけOFF、既存の車両/ルート出勤判定は保持。設定から戻る時に再読取。CI結果、本番migration適用、iPhone Release実機の外部アプリ遷移は未完了。コード/隔離SQL成功を本番導入成功とは扱わない。

参照：Google公式 [Maps URLs](https://developers.google.com/maps/documentation/urls/get-started)、Yahoo公式 [乗換案内](https://transit.yahoo.co.jp/)。GoogleMaps検索URLは `api=1` / `query` のみ。最寄り検索の順位/実際の現在地結果は外部サービスに依存する。
