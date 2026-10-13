import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/help/manual_version.dart';

void main() {
  test('manual version matches pubspec app version', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec);

    expect(match, isNotNull);
    expect(match!.group(1), ManualVersion.appVersion);
  });

  test('manual PDF prints the shared app/manual version label', () {
    final source =
        File('lib/features/help/manual_pdf_service.dart').readAsStringSync();

    expect(source, contains('ManualVersion.label'));
  });
}
