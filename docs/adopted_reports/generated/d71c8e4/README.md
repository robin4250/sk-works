# Flutter生成PDFの検証記録

生成元: d71c8e48b24c4ca19b432dcfc44ad0545a3a386e。GitHub Actions Flutter CI run 37724278115 artifact 11527481622。実際のFlutter PDFサービスとテストデータで生成。架空の検証値であり、本番の給与・承認ではない。

給与タイトルを12pt上へ移動し、給与区分の青枠右側に確認印3枠を追加。確認印サンプルは1番と3番だけ実確認日時を持ち、2番は空欄。日本時間の日付を表示。全22PDFのA4サイズは595.2756×841.8898pt。確認印画像を目視確認し、会社名・角印・タイトル・金額欄の重なりなし。既存支給408248、控除95600、差引312648を維持。

この記録は帳票配置・PDF生成の検証。勤務実績から算出する全金額の組合せ検証、本番承認、iPhone表示・印刷の完了を意味しない。元の採用済みPDFは変更していない。

再生成はCIと同じ `flutter test test/adopted_invoice_pdf_generation_test.dart test/adopted_payroll_pdf_generation_test.dart test/payment_certificate_pdf_generation_test.dart` を使用。テスト用フォントと出力環境は .github/workflows/flutter-ci.yml を参照。
