# 実保存データから生成した給与PDF

生成元コミット: `5d0d702b5127a077b83fde1c2fbf3a39d88a23b8`
Flutter CI run: `37730785208` / artifact: `11528984306`

`test/payroll_persisted_money_pdf_test.dart` が隔離DBの実登録・更新トリガーから保存したfixtureを読み、Flutter PDFを生成しました。5例は日給・時給・月給、夜勤・休日・半日・残業・早出・家族手当・同名手当と控除を含みます。PDF文字座標から支給・控除を合算し、保存総額と差引額に一致するテストは成功しました。実在社員データは含みません。再生成は `test/fixtures/payroll_persisted_money/README.md` を参照してください。

このrun全体は翻訳前の文字列を期待する既存契約テストで失敗しました。実PDF金額検証の成功を全CI成功と混同しません。修正後の最終CIは別途確認します。

28PDF・31ページ全てA4。代表のinvoice v8 / payroll v4 / confirmation stamps / payment certificateを前回b853ba9生成と同じ解像度で比較し、画像差分なし。月給の追加内訳PDFは目視で枠内収まり・金額・独立した合計枠・未登録振込先を確認。iPhoneの表示/印刷確認は未完了です。
