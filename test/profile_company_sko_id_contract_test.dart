import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('profile exposes company SKO ID but not a personal SKO ID', () {
    final page = File('lib/features/profile/profile_page.dart').readAsStringSync();
    final repository =
        File('lib/features/profile/profile_repository.dart').readAsStringSync();

    expect(page, contains("title: const Text('SKO会社ID')"));
    expect(page, contains('SelectableText(data!.companyId)'));
    expect(repository, contains('required this.companyId'));
    expect(repository, contains("memberships.first['company_id']"));
    expect(page, isNot(contains('個人SKO ID')));
  });
}
