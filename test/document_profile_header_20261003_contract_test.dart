import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('self document registration and profile links are available', () {
    final app = File('lib/app_v2.dart').readAsStringSync();
    final profile =
        File('lib/features/profile/profile_page.dart').readAsStringSync();
    final ownDocs = File(
      'lib/features/people/own_document_registration_page.dart',
    ).readAsStringSync();
    final repo = File(
      'lib/features/people/worker_document_repository.dart',
    ).readAsStringSync();
    final migration = File(
      'supabase/migrations/20261003121632_allow_self_document_registration.sql',
    ).readAsStringSync();

    expect(app, contains("key: 'document_register'"));
    expect(app, contains("SkoLanguageController.tr('書類登録')"));
    expect(app, contains("case 'documents':"));
    expect(app, contains("key: 'employee_resources'"));
    expect(File('lib/features/home/employee_resources_page.dart').readAsStringSync(), contains("('documents', '必要書類'"));
    expect(ownDocs, contains("'ログイン中の本人の書類だけを表示します'"));
    expect(ownDocs, contains('saveOwnDocument'));
    expect(ownDocs, contains('repository.loadOwnDocuments()'));
    expect(repo, contains('Future<void> saveOwnDocument'));
    expect(repo, contains('Future<void> updateOwnStatus'));
    expect(repo, contains('Future<Map<String, dynamic>> uploadOwnAttachment'));
    expect(profile, contains('OwnQualificationRegistrationPage'));
    expect(profile, contains('OwnDocumentRegistrationPage'));
    expect(profile, contains("'自分の資格一覧・資格登録'"));
    expect(profile, contains("'自分の登録済み書類・書類登録'"));
    expect(migration, contains('worker can insert own document status'));
    expect(migration, contains('worker can update own document status'));
  });

  test('sub-admin required documents use searchable employee list', () {
    final page =
        File('lib/features/people/worker_document_page.dart').readAsStringSync();
    final repo = File(
      'lib/features/people/worker_document_repository.dart',
    ).readAsStringSync();
    final migration = File(
      'supabase/migrations/20261003122027_allow_subadmin_document_management.sql',
    ).readAsStringSync();

    expect(page, contains("'従業員検索'"));
    expect(page, matches(RegExp(r'onTap:\s*\(\) =>\s*_selectGalleryWorker\(id\)')));
    final selectionStart = page.indexOf('void _selectGalleryWorker(String? worker)');
    final selectionEnd = page.indexOf('ResourceAttachmentGallery? _galleryForWorker', selectionStart);
    expect(selectionStart, greaterThanOrEqualTo(0));
    expect(selectionEnd, greaterThan(selectionStart));
    final selection = page.substring(selectionStart, selectionEnd);
    expect(selection, contains('if (_selectedWorkerId == worker)'));
    expect(selection, contains('_selectedWorkerId = worker'));
    expect(selection, contains('_galleryGeneration++'));
    expect(selection, contains('_galleryChanges.value++'));
    expect(selection, contains('setState(() {})'));
    expect(page, contains('_editStatus(requirement, status)'));
    expect(repo, contains("value.role == 'manager'"));
    expect(migration, contains("'owner','admin','manager'"));
  });

  test('home header opacity applies only to the white band', () {
    final app = File('lib/app_v2.dart').readAsStringSync();
    expect(app, contains('Stack('));
    expect(app, contains('(_homeAppearance.headerOpacity * 255).round()'));
    expect(app, contains('Colors.white.withAlpha('));
    expect(app, contains('backgroundColor: Colors.transparent'));
    expect(app, contains('forceMaterialTransparency: true'));
  });
}
