# 保存済み差引額のPDF検証

生成元 b853ba9d627b5094faebb1e566a9a862618267ee、Flutter CI run 37726895079 artifact 11528296911。帳票生成テストは成功。全体CIは改行依存の別テストで失敗し、4eb17b6で修正。

23 PDF・26ページをpdfinfoで検証し、全ページA4。請求書v8、給与明細v4、確認印付き給与明細、会社角印付き支払証明書をd71c8e4保存PDFと同じ1100pxで描画比較し、画素差なし。新しい検証PDFは保存済み合計12,000円・控除13,000円・差引額0円を使用し、勝手に−1,000円へ再計算しない。0円は既存表示仕様に従い空欄。

再生成: `flutter test test/payment_certificate_pdf_generation_test.dart`。正式採用PDFは変更していない。
