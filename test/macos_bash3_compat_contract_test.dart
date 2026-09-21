import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Mac-day shell helpers avoid Bash 4-only constructs', () {
    final dir = Directory('tool');
    final files = dir
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.sh'));

    for (final file in files) {
      final source = file.readAsStringSync();
      expect(source, isNot(contains('mapfile ')), reason: file.path);
      expect(source, isNot(contains('readarray ')), reason: file.path);
      expect(source, isNot(contains('declare -A')), reason: file.path);
      expect(source, isNot(contains(' -maxdepth ')), reason: file.path);
      expect(RegExp(r'\$\{[^}]+,,\}').hasMatch(source), isFalse,
          reason: file.path);
      expect(RegExp(r'\$\{[^}]+\^\^\}').hasMatch(source), isFalse,
          reason: file.path);
    }
  });
}
