import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('qualification master candidates require explicit admin confirmation', () {
    final page = File(
      'lib/features/qualifications/qualification_master_candidate_review_page.dart',
    ).readAsStringSync();
    final repository = File(
      'lib/features/qualifications/qualification_master_candidate_repository.dart',
    ).readAsStringSync();

    expect(page, contains('自動登録はしません'));
    expect(page, contains('既存資格にまとめますか？'));
    expect(page, contains('新しい資格を作りますか？'));
    expect(page, contains('別名として登録'));
    expect(page, contains('新規資格を作成'));

    expect(repository, contains("membership.role != 'owner'"));
    expect(repository, contains("membership.role != 'admin'"));
    expect(repository, contains("'qualification_master_aliases'"));
    expect(repository, contains("'qualification_master'"));
  });
}
