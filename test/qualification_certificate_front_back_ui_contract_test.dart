import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('qualification certificate page treats back image as optional', () {
    final page = File(
      'lib/features/qualifications/qualification_certificate_page.dart',
    ).readAsStringSync();

    expect(page, contains("'attachment_path'"));
    expect(page, contains("'attachment_back_path'"));
    expect(page, contains("title: '表面'"));
    expect(page, contains("title: '裏面（ない場合は登録不要）'"));
    expect(page, contains('uploadCertificateBack'));
    expect(page, contains('removeCertificateBack'));
    expect(page, contains('表面未登録'));
    expect(page, contains('裏面なし'));
  });
}
