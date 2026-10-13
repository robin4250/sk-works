# 天気取得の接続契約（Issue #273 / PR #945・#963）

2026-10-13更新。現在の採用経路は **OpenWeatherの無料の現在天気＋5日間・3時間ごと予報と、iOS標準の登録住所検索** です。One Call、有料4day、Googleの追加契約・請求先登録は行いません。鍵名だけを記載し、秘密値は記録・表示しません。

## 現在の接続と確認状態

| 段階 | 確認した状態 |
|---|---|
| main実装 | 無料API・native iOS住所検索・ホーム取得接続を反映済み |
| 本番Supabase | fetch-weather-forecast関数反映、既存provider設定のopenweather、OpenWeatherキー登録を確認済み |
| 提供元API | ユーザーのMacでweather・forecastとも取得成功を確認済み。以前の401記録は成功前の履歴 |
| アプリ表示 | 2026-10-13 08:48 JSTのユーザー実機確認で天気カード表示を確認 |
| 最新Releaseの実機検証 | 上記表示確認後の最新main全体については導入・表示・操作の完了とは扱わない。最新Releaseで再確認が必要 |
| WeatherKit | 切替adapter/UIは存在するが、必要設定・実API・実機成功は未確認 |

実APIの成功、本番秘密設定、アプリ表示、最新Releaseの全機能検証は別の証拠です。現在の文書はmain `82538dd0`のソースを確認して更新しています。

## 無料OpenWeatherの取得

`fetchOpenWeather` は `https://api.openweathermap.org/data/2.5/forecast` を取得します。選択日が表示地域の今日の場合だけ `https://api.openweathermap.org/data/2.5/weather` も取得します。緯度経度とserver保持キーを使い、`units=metric`、`lang=ja`で呼びます。現在天気だけ失敗しても取得済みの予報は保持します。

予報のsourceは`list.dt`、`list.main.temp`、`list.pop`、`list.weather[0].id`です。降水確率だけ0〜1から％へ変換します。One Call 3/4や`pro.openweathermap.org`の有料hourlyは呼びません。`OPENWEATHER_HOURLY_PRODUCT`は現在のadapterでは参照しません。

今日・明日・明後日の0/3/6/9/12/15/18/21/24時の9枠を表示します。24時は選択日の翌日0時です。地域のIANA timezoneへ変換したsource時刻がその枠に完全一致し、一意である場合だけ使います。過去の時刻は無料予報APIから取得できないため未取得になり、欠損・重複もnullです。0℃・0％の補完、平均、丸めた時刻の付替えは行いません。地域によって3時間予報の時刻が表示枠に一致しない場合も未取得です。

今日の現在天気はsource timestampが地域の今日に属する場合だけ表示します。未来日の代表値はその日の実取得12時枠、欠損時は実取得0〜21時の最初の枠で、`summary_hour`を返します。未来日に現在気温を借用しません。

**無料OpenWeather経路の`rain_approach`は常にnullです。** 3時間の降水量や降水確率から分単位の雨接近・到着ETA・「雨なし」を推測しません。

## 登録住所とnative iOSの2段階契約

サーバーは本人BearerをAuthで検証し、同じBearerでRLS対象の会社／本人自宅／単一固定勤務現場の登録住所を読みます。社員作成やGPS現在地の読取は行いません。会社行取得失敗を住所未登録と扱わず、route、複数勤務、48時間を超える未解決勤務、取得上限は未取得にします。ルートのclock-in現場を現在訪問先と推測しません。

1. iOS gatewayが`day_offset: 0|1|2`と`prepare_location: true`を送ります。serverが解決した`address`、`region_kind`、`region_token`を返します。
2. MethodChannel `sko.capture_metadata`の`weatherGeocode`で、登録住所を`CLGeocoder.geocodeAddressString`へ渡します。単一候補・有効座標・timezone・country・localityを要求し、15秒で検索を打ち切ります。生成元`tool/prepare_ios.sh`にも処理を保持しています。
3. gatewayは同じ本人を再確認し、`day_offset`、`native_location`、`region_token`を送ります。nativeの許可fieldは`latitude`、`longitude`、`time_zone`、`country_code`、`source: apple_native`です。
4. serverが登録住所を読み直し、本人ID・住所種別・住所文字列から算出したSHA-256とtokenを照合します。本人／住所が変わった結果を拒否し、座標範囲・IANA timezone・国コードを検証して地域日付を決めます。

任意の住所・actor・provider指定は受け付けません。tokenは現在の本人・登録住所への結び付けであり、ログイン認証を代替しません。座標とtimezoneは端末のApple検索結果を信頼する境界で、サーバーによる独立した住所地理照合ではありません。Apple検索はネットワークを使うため、通信失敗・曖昧候補は未取得になります。

このnative経路はiOS専用です。Google APIキーは不要で、他platformの対応完了とは扱いません。旧Google adapterはソースに残りますが、`WEATHER_GEOCODING_PROVIDER=google`と鍵を明示しない限り使えず、現在の採用経路として設定しません。

## 設定と権限

| 名前 | 現在の扱い |
|---|---|
| SUPABASE_URL | Edge Functionの対象project |
| SUPABASE_PUBLISHABLE_KEYS.default | public API key。legacy SUPABASE_ANON_KEYへfallback。本人読取にservice_roleを使わない |
| OPENWEATHER_API_KEY | serverのみ。登録成功確認済み、値は出力しない |
| OPENWEATHER_HOURLY_PRODUCT | 現在は不要・参照しない |
| WEATHER_GEOCODING_PROVIDER / WEATHER_GEOCODING_API_KEY | native iOS経路では不要。Googleの契約・請求先登録は進めない |
| WEATHERKIT_TEAM_ID / WEATHERKIT_SERVICE_ID / WEATHERKIT_KEY_ID / WEATHERKIT_PRIVATE_KEY | 将来WeatherKitを利用する場合に別途確認が必要。現時点で追加設定・契約は行わない |

`private.weather_provider_settings`は既存traffic/master flagsと別です。現在providerはopenweather。本人認証済みの読取、既存`is_current_user_master_admin`による変更、直接テーブルアクセス不可の契約を保持します。WeatherKitはApple Developer登録・service/key・server ES256 tokenとattribution確認が必要です。切替UIがあることを実取得成功と扱いません。

Yahoo!雨雲レーダーは別系統です。sourceの国コードがJPの時だけ公開ページURLを返し、推測の位置queryは付けません。分単位予報を得られるWeatherKitの将来経路は公式availabilityがNextHourを提供する場合だけ対象とし、無料OpenWeatherで同じ機能が使えるとは表示しません。

## 検証と残る確認

無料endpoint、現在天気失敗時の予報保持、未来日・24時・欠損、認証・本人住所変更・native準備、秘密非露出はNodeテストで検証しました。Flutter gateway/cardとiOS生成処理の検査・CIを経てmainへ反映しています。実キーを使うAPI呼出と実機表示は上表のユーザー確認で別に記録しています。

残る実機確認は最新Releaseでの今日／明日／明後日の切替、詳細の9枠・未取得表示、住所source変更、Yahoo導線、attribution、晴れのオレンジ／雨の青い傘の表示です。ルート現在訪問先の住所adapter、iOS以外、WeatherKit実接続は完了扱いにしません。同地域の再取得失敗時は既存予報と更新日時を保持し、地域変更では古い地域の値を消す既存契約を維持します。

## 一次資料（2026-10-13確認）

- [OpenWeather Current weather](https://openweathermap.org/api/current)：data/2.5/weather、metric温度、source timestamp。
- [OpenWeather 5 day / 3 hour forecast](https://openweathermap.org/api/forecast5)：data/2.5/forecast、3時間予報、pop。
- [Apple CLGeocoder](https://developer.apple.com/documentation/corelocation/clgeocoder) / [Apple公式Geocoding guide（archive）](https://developer.apple.com/library/archive/documentation/UserExperience/Conceptual/LocationAwarenessPG/UsingGeocoders/UsingGeocoders.html)：住所のforward geocodingと通信依存。archiveは現在のAPI推奨や無料無制限を保証する資料としては使わない。
- [Apple WeatherKit](https://developer.apple.com/weatherkit/)：Developer Programと別途service設定が必要な将来経路。
- [WeatherKit REST token](https://developer.apple.com/documentation/weatherkitrestapi/request-authentication-for-weatherkit-rest-api)

旧One Call・有料hourly・Googleのみ・401未成功の記述は、導入途中の記録として[2026-10-12引継ぎ](WEATHER_CARD_HANDOFF_20261012.md)に保持しています。この文書の現在契約はそれらを置き換えます。
