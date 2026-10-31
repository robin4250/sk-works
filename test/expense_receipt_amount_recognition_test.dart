import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/expenses/expense_receipt_amount_recognition.dart';

void main() {
  test('Japanese total is preferred over tender, change, subtotal and tax', () {
    final result = ExpenseReceiptAmountRecognition.parse('小計 1,000円\n消費税 100円\n合計 ¥1,100\nお預り ¥2,000\nお釣り 900円');
    expect(result.unambiguousTotal, 1100);
    expect(result.candidates.map((c) => c.amountYen), [1100]);
  });
  test('full width digits and wrapped total are accepted as candidates', () {
    final result = ExpenseReceiptAmountRecognition.parse('税込合計\n￥１，２３４');
    expect(result.unambiguousTotal, 1234);
  });
  test('conflicting totals require a human choice rather than largest amount', () {
    final result = ExpenseReceiptAmountRecognition.parse('合計 1,100円\n領収金額 ¥900');
    expect(result.unambiguousTotal, isNull);
    expect(result.candidates.map((c) => c.amountYen), [1100, 900]);
  });
  test('unlabelled currency is never an automatic total', () {
    final result = ExpenseReceiptAmountRecognition.parse('テープ ¥500\n送料 100円');
    expect(result.unambiguousTotal, isNull);
    expect(result.candidates, hasLength(2));
  });
  test('dates, phones, zero, negative, decimal and malformed money are not totals', () {
    for (final text in ['2026/11/01\n03-1234-5678', '合計 0円', '合計 -100円', '合計 1,23円', '合計 12.50円', '合計 1000000000円']) {
      expect(ExpenseReceiptAmountRecognition.parse(text).unambiguousTotal, isNull, reason: text);
    }
  });
  test('repeated same total is deduplicated without treating tax as a candidate', () {
    final result = ExpenseReceiptAmountRecognition.parse('合計 1,200円\n領収金額 ¥1,200\n内税 109円');
    expect(result.unambiguousTotal, 1200);
    expect(result.candidates, hasLength(1));
  });
  test('negative conventions never become positive currency candidates', () {
    for (final text in ['合計 －100円','合計 ▲100円','合計 △100円','合計 −100円',
      '合計 (100円)','合計 （￥１００）','合計 100円－','合計 —¥100',
      '合計\n－100円','合計\n¥100\n▲','合計\n▲\n100円',
      '合計 ￥−100円','合計 ¥100−','合計 (¥100)円','合計 マイナス100円',
      'マイナス\n合計 100円','▲\n合計\n100円','合計 −\n100円',
      '合計 (\n100円\n)','¥▲\n合計\n100円']) {
      final result = ExpenseReceiptAmountRecognition.parse(text);
      expect(result.candidates,isEmpty,reason:text);
      expect(result.unambiguousTotal,isNull,reason:text);
    }
  });
  test('a negative item discount does not become a candidate or erase a positive total', () {
    final result = ExpenseReceiptAmountRecognition.parse('値引 -100円\n合計 1,000円');
    expect(result.unambiguousTotal,1000);
    expect(result.candidates.map((c) => c.amountYen),[1000]);
  });
  test('refund or cancellation labels on another line require manual review', () {
    for (final label in ['返金','返品','取消','払戻','キャンセル']) {
      expect(ExpenseReceiptAmountRecognition.parse('$label\n合計 ¥1,000').candidates,isEmpty,reason:label);
    }
  });
  test('failure and excessive ambiguous input do not invent a zero amount', () {
    expect(ExpenseReceiptAmountRecognition.parse('').candidates, isEmpty);
    expect(ExpenseReceiptAmountRecognition.parse(List.generate(13, (i) => '商品 ¥${i + 1}').join('\n')).candidates, isEmpty);
  });
}
