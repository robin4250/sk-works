import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('worker private documents are scoped to self or people managers', () {
    final workerDocs =
        File('lib/features/people/worker_document_repository.dart')
            .readAsStringSync();
    final qualifications =
        File('lib/features/qualifications/qualification_certificate_repository.dart')
            .readAsStringSync();
    final qualificationCloud =
        File('lib/features/qualifications/qualification_cloud_repository.dart')
            .readAsStringSync();
    final page =
        File('lib/features/qualifications/qualification_certificate_page.dart')
            .readAsStringSync();

    expect(workerDocs, contains("permissions['can_manage_people'] == true"));
    expect(workerDocs, contains("rpc('ensure_current_user_worker')"));
    expect(workerDocs, contains("statusesQuery.eq('worker_id', ownWorkerId)"));

    expect(qualifications, contains("permissions['can_manage_people'] == true"));
    expect(qualifications, contains("rpc('ensure_current_user_worker')"));
    expect(
      qualifications,
      contains("qualificationsQuery.eq('worker_id', ownWorkerId)"),
    );
    expect(
      qualificationCloud,
      contains("permissions['can_manage_people'] == true"),
    );
    expect(
      qualificationCloud,
      contains("qualificationsQuery.eq('worker_id', ownWorkerId)"),
    );
    expect(page, contains('if (_canManage)'));
    expect(page, contains('資格証写真はまだ登録されていません。'));
  });
}
