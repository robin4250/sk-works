import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/help/manual_content.dart';

void main() {
  test('manuals never direct submission of individual number or card back', () {
    final manuals = [ManualContent.general, ManualContent.subAdmin,
      ManualContent.admin, ManualContent.pamphlet];
    const sensitiveTitles = {'本人情報・本登録', '本登録', '従業員の本登録承認',
      '必要書類', '必要書類・資格証', '本人の書類・資格カード', '社員の書類・資格カード'};
    for (final manual in manuals) {
      for (final section in manual) {
        final instructions = '${section.summary} ${section.steps.join(' ')}';
        expect(instructions, isNot(matches('マイナンバー|個人番号')),
          reason: section.title);
        if (sensitiveTitles.contains(section.title)) {
          expect(section.support, contains('個人番号'), reason: section.title);
          expect(section.support, contains('裏面'), reason: section.title);
          expect(section.support, matches('しない|求めない'), reason: section.title);
        }
      }
    }
  });
}
