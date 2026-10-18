import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production qualification route uses the cloud registration flow', () {
    final app = File('lib/app_v2.dart').readAsStringSync();
    final cloud =
        File('lib/features/qualifications/qualification_cloud_page.dart')
            .readAsStringSync();

    expect(app, contains('SupabaseBackend.isInitialized'));
    expect(app, contains('const OwnQualificationRegistrationPage()'));
    expect(app, contains('const QualificationCloudPage()'));
    expect(cloud, contains('Future<void> _addQualification({String? initialMasterId})'));
    expect(cloud, contains("initialMasterId: row['qualification_master_id']?.toString()"));
    expect(cloud, contains('insertWorkerQualification('));
    expect(cloud, contains("title: const Text('従業員資格')"));
    expect(cloud, contains("hintText: '従業員名で検索'"));
    expect(cloud, contains("hintText: '資格種類・証明書番号で検索'"));
  });

  test('registered certificate photos are readable while manager changes await approval', () {
    final source =
        File('lib/features/qualifications/qualification_certificate_page.dart')
            .readAsStringSync();

    // New photo uploads would directly PATCH an already registered row.
    expect(source, isNot(contains('ImageSource.camera')));
    expect(source, isNot(contains('ImageSource.gallery')));
    expect(source, contains('registeredQualificationChangeNotice'));
    expect(source, contains('createSignedUrl('));
  });
}

