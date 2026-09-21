import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('required documents and qualifications do not use secondary auth', () {
    final source = File('lib/app_v2.dart').readAsStringSync();

    expect(
      source,
      isNot(
        contains(
          "const SecondaryProtectedPage(\n"
          "          title: '必要書類',\n"
          "          child: WorkerDocumentPage(),",
        ),
      ),
    );
    expect(
      source,
      isNot(
        contains(
          "const SecondaryProtectedPage(\n"
          "          title: '資格証',\n"
          "          child: QualificationCertificatePage(),",
        ),
      ),
    );

    expect(source, contains("page = const WorkerDocumentPage();"));
    expect(source, contains("page = const QualificationCertificatePage();"));
  });
}
