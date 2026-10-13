import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('site detail hides empty values and uses a compact two-column grid', () {
    final page = read('lib/features/sites/site_detail_page.dart');

    expect(page, contains('final trimmed = value.trim();'));
    expect(page, contains('if (trimmed.isEmpty) return const SizedBox.shrink();'));
    expect(page, contains('constraints.maxWidth >= 360'));
    expect(page, contains('(constraints.maxWidth - gap) / 2'));
    expect(page, contains('return Wrap('));
    expect(page, contains('runSpacing: 6'));
  });

  test('site detail keeps registrant read-only and actions compact', () {
    final page = read('lib/features/sites/site_detail_page.dart');

    expect(page, contains("_tr('登録者 ', 'Registrant ')"));
    expect(page, contains('onTap: _showCreator'));
    expect(page, contains("_tr('共有', 'Share')"));
    expect(page, contains("_tr('編集／登録', 'Edit / Register')"));
    expect(page, contains('height: 38'));
  });
}
