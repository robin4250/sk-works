import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pre-device readiness documents current release guarantees', () {
    final doc = File('docs/PRE_DEVICE_READINESS.md').readAsStringSync();

    expect(doc, contains('every push and pull request'));
    expect(doc, contains('exactly on `main`'));
    expect(doc, contains('origin/main'));
    expect(doc, contains('generated iOS permission/orientation/bundle-ID contract'));
    expect(doc, contains('SHA-256 checksums'));
    expect(doc, contains('bash tool/device_day.sh'));
    expect(doc, contains('bash tool/supabase_repro_preflight.sh'));
  });

  test('iPhone acceptance checklist covers latest security-critical flows', () {
    final doc = File('docs/IPHONE_ACCEPTANCE_TEST.md').readAsStringSync();

    const required = [
      '本パスワードを忘れた方',
      'SMS確認成功後に即時更新される',
      'バックグラウンドへ送り、戻ると再認証を要求する',
      '撮影キャンセル時は登録されない',
      '印刷PDFにも手書き責任者サインが表示される',
      '他人の給与明細を一般ユーザーが読めない',
      '一般ユーザーは他人の必要書類・資格証を読めない',
      'iPhone縦画面で横切れしない',
    ];

    for (final item in required) {
      expect(doc, contains(item), reason: 'Missing acceptance item: $item');
    }
  });
}
