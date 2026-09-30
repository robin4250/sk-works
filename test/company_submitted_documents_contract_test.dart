import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('company submitted documents reuse the secure company exchange', () {
    final page = File(
      'lib/features/people/company_submitted_documents_page.dart',
    ).readAsStringSync();
    final repository = File(
      'lib/features/people/company_submitted_document_repository.dart',
    ).readAsStringSync();

    expect(repository, contains("'company_required_documents'"));
    expect(repository, contains("'company-required-documents'"));
    expect(repository, contains("'scope': 'upstream'"));
    expect(repository, contains("update({'is_active': false})"));

    expect(page, contains("title: const Text('会社提出書類')"));
    expect(page, contains("'kind': 'company'"));
    expect(page, contains('resolveReceiveCode'));
    expect(page, contains('送信内容の最終確認'));
    expect(page, contains('FilePicker.pickFile'));
  });
}
