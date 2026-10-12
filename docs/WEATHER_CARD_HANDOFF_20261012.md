# 天気予報カード（2026-10-12）

ユーザーは天気予報カードの並走開始、見本の多色ではなくSKO既存配色への統一を依頼。
Issue #273本文/全432コメントとrepo検索には天気の仕様が無かったが、rootが過去の確定指示を取得して以下を引き継いだ。参照画像の23℃/15℃/20%は例示で、実際の予報に使わない。

## 確定仕様

- ホーム横長カード。初期位置は「本日の出勤」と「要対応」の間。
- 要対応と同寸の枠。長押しで上下移動、メニューのスイッチで表示/非表示。表示ONで取得不可でも枠を残す。
- 小さい説明「出勤前：自宅周辺 ／ 出勤後：現場周辺の天気を表示」。既存Themeのprimary/surface/outlineを使用し、多色を追加しない。
- 管理者：会社未登録/住所無しは会社住所設定案内、登録後は会社周辺。
- 社員：参加時/本人住所登録前は会社周辺。本人住所登録後は出勤前に自宅周辺、出勤中は選択/登録済み現場住所周辺。GPS現在地ではない。
- 現在の天気、気温、晴/曇/雨/雪等アイコン、降水確率、雨接近情報。今日/明日/明後日の各日0〜24時を3時間ごとの9区分（0/3/6/9/12/15/18/21/24）。ユーザーの最新指示により◀をカード左端、▶を右端に配置し選択日を中央に表示。◀/▶で3日間を切替、今日より前/明後日より先は無効。選択日をホーム/詳細で同期する。
- 通常予報はOpenWeather初期、Apple WeatherKitへ切替可能。選択できるのはマスター管理者のみ（サーバーでも検証が必要）。
- Yahoo!天気の雨雲レーダーボタンは別系統・差替可能。日本など提供元が対応する地域だけに出し、非対応国は非表示。
- SKOの共通言語ファイルと？ヘルプを使用する。

## 実装した範囲

`WeatherForecastHomeCard`は共通`HomeInformationCard`で要対応と同じ幅/高さ/枠/青の帯を使う。
文字拡大時は両方の高さを同じ式で伸ばし、通知最大3行を保持。気温は地域/天気の省略に巻き込まれない独立表示枠。天気の持ち手だけ青帯の左下へ移し、◀▶の44px入力領域と重ならない。既存の他の持ち手位置とStackFit.passthroughを保持。天気の時間別詳細はカードを押して開く。
既存メニューのホーム表示設定と並び順にweather_forecastを追加。初回は本日の出勤直後、要対応はその次。
ヘッダー、既存給与、帳票、DB schema/保存/データは変更しない。

`HomeWeatherLocationRepository`は既存のcompany_members/companies/sitesのSELECTとcurrent_worker_personnel_profile RPCを読み取るだけ。
actor/会社で範囲を限定し、会社住所の空文字と会社行の取得不可を区別。複数の勤務開始/現場不明の場合は現場を推測せず未取得。ルート勤務のclock_in.site_idは現在visitの証拠ではないため利用しない。現在visit住所のadapterは未完了。
ホーム読み込み、勤務/プロフィール/会社設定から戻った際に住所sourceを更新する。日付が変わった後のアプリ復帰・矢印操作・更新でも日付を更新し旧日の予報を消す。
読み込み失敗を「会社未登録」と誤表示しない。

`WeatherForecastController`は登録済み住所とサーバーfetch callbackの境界。
同地域の再取得失敗は古い予報/更新日時を保持し、地域変更時は旧予報を消す。遅い旧地域応答で新現場を上書きしない。
選択日ごとの9区分は提供元の欠損を0℃/0%に置き換えず「未取得」と表示する。
表示日時は提供元adapter側で表示地域の時刻へ正規化して渡す。現在のbaseDateは端末日付。実API接続時に地域timezone/date契約を確定する。fetchは対象日付を明示し別日の応答を拒否する。未来日の代表天気/気温の提供元フィールドは取得契約で確定し、現在天気を未来の日付へ付け替えない。24時は選択日の翌日0時の区分であり、adapterが別の日の0時と混同せず渡す。

## 未完了/未検証

**現在の実ホームは枠・住所source・未取得表示まで接続。実予報を取得していない。**
rootがSupabaseの一意なSK WORKS project ztktgquxvcxcjxtluspu（ACTIVE_HEALTHY）の13 Edge Functionsをread-only確認し、weather/forecast/radar名の関数は無かった。secret/API key値は取得しておらず、本番credential存在は未確認。repoに鍵名が無いだけで「本番にもない」と断定しない。
API認証/取得契約、住所geocoding、提供元別レスポンス正規化、サーバーでのmaster選択保存・検証、雨接近データ、Yahoo日本地域判定/外部導線接続は未完了。
クライアントへAPI秘密鍵を追加していない。Supabase schema/本番関数/本番dataを変更していない。

根拠となる一次資料：
- https://openweathermap.org/api （現行一覧ではOne Call 3.0がdeprecated、4.0への移行が案内。API版は契約確認後に決定）
- https://developer.apple.com/documentation/weatherkitrestapi/request-authentication-for-weatherkit-rest-api （開発者tokenによる認証）
- https://developer.apple.com/weatherkit/ （REST対応、時間別予報）
- https://weather.yahoo.co.jp/weather/zoomradar/ （別サービスの雨雲レーダー）
- https://supabase.com/docs/reference/dart/select （既存SELECT/filtersを使用）
- Supabase changelog.mdは閲覧toolでunsupported content-type、https://supabase.com/changelogのHTMLを確認。今回の既存Dart SELECTへの関連breaking-changeは確認できず。

テストは320px/文字1.3倍の9区分横スクロール、共有寸法、既存通知保持、初期配置/設定順/非表示、住所未登録と読込失敗の区別、住所sourceのactor/会社scope、変更地域の応答競合を確認する。
ローカルFlutter未実行。Dart構文/整形確認とFlutter CIを区別。iPhone実機未確認。


## 2026-10-13 更新（最新仕様）
追加契約・請求先登録は行わない。OpenWeatherは無料のdata/2.5/weatherとdata/2.5/forecastへ変更。One Call・有料4dayを呼ばず、分単位雨接近はnull。iOS標準CLGeocoderで登録住所を検索する。サーバーが本人の住所を準備し、本人・住所種別・住所のSHA256を再確認して検索結果を受け取る。座標・国・タイムゾーンは端末の検索結果であり、サーバーでの独立した地理検証ではない。Google APIキーは不要。iOS以外は現時点で未対応。prepare_ios.shにも検索処理を追加。Node18件・Flutter24件成功、Dart解析とSwift構文成功。関数は本番へ反映済み。実APIは401のため未成功、Releaseビルド・実機確認は未完了。
