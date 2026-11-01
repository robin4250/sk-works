import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('private worker views fail closed when current worker link is absent', () {
    for (final path in [
      'lib/features/qualifications/qualification_certificate_repository.dart',
      'lib/features/qualifications/qualification_cloud_repository.dart',
    ]) {
      final source = File(path).readAsStringSync();
      final load = source.substring(source.indexOf('Future<Map<String, dynamic>> loadAll()'), source.length);
      expect(load, contains('await scope.ownWorker()'), reason: path);
      expect(source, contains('QualificationDocumentReadScope.capture(_client)'), reason: path);
    }
    final scope = File('lib/features/qualifications/qualification_document_read_scope.dart').readAsStringSync();
    expect(scope, contains(".eq('company_id', companyId).eq('user_id', actor)"));
    expect(scope, contains('.limit(2)'));
    expect(scope, isNot(contains(".inFilter('status'")));
    expect(scope, contains("!const ['active', 'inactive'].contains(rows.single['status'])"));
    expect(scope, contains('rows.length != 1'));
    expect(scope, contains("rows.single['user_id'] != actor"));
    expect(scope, isNot(contains("rpc('ensure_current_user_worker')")));
    final workerDocs = File('lib/features/people/worker_document_repository.dart')
        .readAsStringSync();
    final loadStart = workerDocs.indexOf('>>>> loadAll(');
    final loadEnd = workerDocs.indexOf('>>>> loadOwnDocuments()', loadStart);
    expect(loadStart, greaterThanOrEqualTo(0));
    expect(loadEnd, greaterThan(loadStart));
    final load = workerDocs.substring(loadStart, loadEnd);
    expect(load, isNot(contains("rpc('ensure_current_user_worker')")));
    expect(load, contains(".eq('company_id', companyId).eq('user_id', actor!)"));
    expect(load, contains(".inFilter('status', ['active', 'inactive']).limit(2)"));
    expect(load, contains('rows.length != 1'));
    expect(load, contains("rows.single['user_id'] != actor"));
    expect(load, contains("throw StateError('本人の保存済み書類を確認できません。')"));
  });
}
