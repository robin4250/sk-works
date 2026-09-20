import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('private worker documents stay behind secondary authentication', () {
    final source = File('lib/app_v2.dart').readAsStringSync();

    expect(
      source,
      contains(
        "const SecondaryProtectedPage(\n          title: '必要書類',\n          child: WorkerDocumentPage(),",
      ),
    );
    expect(
      source,
      contains(
        "const SecondaryProtectedPage(\n          title: '資格証',\n          child: QualificationCertificatePage(),",
      ),
    );
  });
}
