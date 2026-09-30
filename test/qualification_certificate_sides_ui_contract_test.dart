import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('qualification certificate UI treats back image as optional', () {
    final source = File(
      'lib/features/qualifications/qualification_certificate_page.dart',
    ).readAsStringSync();

    expect(source, contains("label: '表面'"));
    expect(source, contains("label: '裏面（ない資格証は未登録でOK）'"));
    expect(source, contains('uploadCertificateBack'));
    expect(source, contains('removeCertificateBack'));
    expect(source, contains('attachment_back_path'));
  });
}
