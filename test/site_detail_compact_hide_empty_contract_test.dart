import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('site detail uses compact two-column layout and hides empty fields', () {
    final source =
        File('lib/features/sites/site_detail_page.dart').readAsStringSync();

    expect(source, contains('final fieldWidth = constraints.maxWidth >= 340'));
    expect(source, contains('return Wrap('));
    expect(source, contains('if (trimmed.isEmpty) return const SizedBox.shrink()'));
    expect(source, contains('maxLines: maxLines'));
    expect(source, isNot(contains("'未登録', 'Not registered'")));
  });

  test('site detail keeps registrant as history-only detail', () {
    final source =
        File('lib/features/sites/site_detail_page.dart').readAsStringSync();

    expect(source, contains("_tr('登録者 ', 'Registrant ')"));
    expect(source, contains('site.creatorName'));
    expect(source, isNot(contains("controller: _creator")));
  });
}
