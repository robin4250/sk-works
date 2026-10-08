import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/payroll_condition_warning.dart';
import 'package:sk_works/international/language_controller.dart';
import 'package:sk_works/international/language_pack_registry.dart';

void main() {
  setUp(() => SkoLanguageController.pack.value = LanguagePackRegistry.resolve('ja'));
  tearDown(() => SkoLanguageController.pack.value = LanguagePackRegistry.resolve('ja'));

  test('known server templates translate while employee names stay unchanged', () {
    SkoLanguageController.pack.value = LanguagePackRegistry.resolve('en');
    const warning = '山田太郎：有給2日：日給・時給の有給支給額は現在の自動計算に含まれていません。会社の有給給与条件と支給額を確認してください。';
    expect(localizedPayrollConditionWarning(warning), startsWith('山田太郎：2 paid-leave days:'));
    expect(localizedPayrollConditionWarning('山田太郎：独自の会社条件'), '山田太郎：独自の会社条件');
    const monthly = '月給の休日勤務・夜勤実績に未登録の単価があります。会社の追加支給条件と給与設定を確認してください。';
    final translatedMonthly = localizedPayrollConditionWarning(monthly);
    expect(translatedMonthly, contains('${SkoLanguageController.tr('休日勤務')} / ${SkoLanguageController.tr('夜勤')}'));
    expect(translatedMonthly, startsWith('Monthly-pay records for '));
    expect(translatedMonthly, contains('have missing rates.'));
    expect(translatedMonthly, isNot(contains('休日勤務')));
    expect(translatedMonthly, isNot(contains('夜勤')));
  });
  test('warnings accept only distinct nonempty strings', () {
    expect(payrollConditionWarnings({'calculation_warnings': [' 条件確認 ', null, 10, '', '条件確認']}), ['条件確認']);
    expect(payrollConditionWarnings({'calculation_warnings': 'invalid'}), isEmpty);
  });

  testWidgets('confirmation requires explicit acknowledgment and can return', (tester) async {
    bool? accepted;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      return TextButton(onPressed: () async {
        accepted = await confirmPayrollConditions(context, ['有給支給額を確認してください']);
      }, child: const Text('確認'));
    })));
    await tester.tap(find.text('確認'));
    await tester.pumpAndSettle();
    expect(accepted, isNull);
    await tester.tap(find.text('戻って確認'));
    await tester.pumpAndSettle();
    expect(accepted, isFalse);
    await tester.tap(find.text('確認'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('条件と金額を確認して続行'));
    await tester.pumpAndSettle();
    expect(accepted, isTrue);
  });
}
