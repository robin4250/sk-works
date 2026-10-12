# 天気取得の接続契約（Issue #273 / PR #945）

本ソースは本番へ未導入。実API認証・本番schema・実機成功を意味しません。APIキーの値を記録・表示しません。

## 実装

`fetch-weather-forecast/index.ts` は認証済み本人のBearerでAuthとRLS対象RESTを読み、会社／本人の自宅／単一固定勤務現場の住所を解決します。天気のために社員を作成しません。会社行取得失敗を住所未登録と扱いません。ルートのclock-in現場を現在現場として使わず、route・複数勤務・48時間を超える未解決出勤・取得件数上限は未取得へ倒します。server住所resolverとHOMEの既存出勤日付判定には保守的な差があり、長期勤務・ルート現在訪問の統合確認が残ります。

クライアントの入力は `day_offset: 0|1|2` のみ。住所／緯度経度／provider／actorの指定は受け付けません。server住所のIANA timezoneから `base_date` と `forecast_date` を決定。24時は選択日の翌日0時。同じ時刻が重複・欠損なら値はnull。source値と％以外の平均・補完をしません。未来日は現在気温を借用せず、選択日の12時（欠損時は実取得済み0〜21時の最初の枠）をsummary_hourと共に返します。現在データもsource timestampが地域の今日に属する時だけ使用します。Flutter `WeatherForecastGateway` は本人変更／レスポンス日付／9枠／数値範囲を検証し、sourceconditionを晴曇雨雪等の既存翻訳経路とアイコンへ変換します。

新規private `weather_provider_settings` は既存traffic等のmaster flagsと別テーブル。初期OpenWeather。本人認証済み読取、変更は既存 `is_current_user_master_admin` だけ。public RPCはsecurity invoker、private実装が認証/MASTER確認を行い、テーブルの直接アクセスは許可しません。migrationはSupabase CLI `migration new` で生成。production未適用。MASTER選択部品 WeatherProviderSettingsPanel は実装済み、HOME fetch hookと既存マスター画面への挿入は共有file担当との直列接続が残ります。

## 本番で必要な設定（未確認）

| 設定 | 必要な内容 |
|---|---|
| SUPABASE_URL | 対象SK WORKS projectのURL |
| SUPABASE_PUBLISHABLE_KEYS.default | public API key（legacy SUPABASE_ANON_KEYへfallback）。service_roleは使わない |
| OPENWEATHER_API_KEY | 所有者が契約済みのkey。OneCall3 accessが必要 |
| OPENWEATHER_HOURLY_PRODUCT | `4day` なら別契約の4日hourlyを追加取得。未設定ならOneCall48h範囲だけ、day2欠損はnull |
| WEATHERKIT_TEAM_ID / SERVICE_ID / KEY_ID | Apple Developer登録済みWeatherKit service/keyの識別子 |
| WEATHERKIT_PRIVATE_KEY | serverのみのP-256 PKCS8 PEM。5分ES256 JWTを発行 |
| WEATHER_GEOCODING_PROVIDER | `google` を明示した時だけ住所lookup有効 |
| WEATHER_GEOCODING_API_KEY | Google Geocoding＋Time Zone権限を持つserver key。利用契約/課金/制限設定は所有者確認が必要 |

Google adapterは単一のROOFTOPかつpartial_matchでない住所を必須にし、曖昧な住所や市中心を推測しません。外部契約未確認のため勝手にAPIを契約・購入・secret登録しません。住所建物情報等で正確照合しない場合は未取得。外部提供先への住所送信とattribution/契約は本番導入前の確認事項です。Yahoo radarは独立系統、serverのcountryCode=JPのみ公開ページURLを返します。位置中心指定の公式URL契約は未確認のため推測のqueryを付けません。詳細ボタン接続と実機での開き方確認が残ります。

## 検証と残る作業

Node24の14テストで両HTTPprovider、WeatherKit実ES256署名verify、地域日付・24時・48h欠損、4dayfixture、actor scoped住所、曖昧geocode、認証、入力override拒否、secret非露出を検証。PGlite0.3.14の実SQLで通常社員の更新拒否、MASTER変更、直接テーブル拒否、匿名拒否、無効値拒否、migration replayでprovider保持、既存traffic値保持を確認。本物APIは呼びません。

Flutter新gateway2テストはCI対象、ローカルFlutterは未実行。HOME/controllerへregion baseDate/取得状態を接続、MASTER provider選択UI、Apple returned trademark画像＋legalリンク部品とOpenWeather attribution部品は実装済み、詳細への挿入・実画像表示確認が残ります。Yahoo国判定/ボタン、rain approach説明、未来日代表値のHOME表示接続が残ります。server function/migration未導入。API契約・秘密設定確認→本番導入→両provider実API→iPhone Release確認が必要です。

## 確認した一次資料

- https://openweathermap.org/api/one-call-3 （OneCall48h、metric Celsius、timezone）
- https://openweathermap.org/api/one-call-4 （新APIもhourly48h。契約を勝手に4へ切替しない）
- https://openweathermap.org/api/hourly-forecast （pro4dayHourly、別商品）
- https://developer.apple.com/documentation/weatherkitrestapi/request-authentication-for-weatherkit-rest-api
- https://developer.apple.com/weatherkit/ （AppleWeather trademark＋他datasources legal attribution。RESTは10dayhourly、ADP membershipが必要）
- https://developers.google.com/maps/documentation/geocoding/requests-geocoding
- https://developers.google.com/maps/documentation/timezone/requests-timezone
- https://supabase.com/docs/guides/functions/auth

API利用料・アカウント登録・購読操作は行っていません。
