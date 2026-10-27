import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/qualifications/qualification_cloud_page.dart';
import 'package:sk_works/features/qualifications/qualification_cloud_repository.dart';
import 'package:sk_works/features/qualifications/qualification_certificate_repository.dart';

class _Repository implements QualificationCloudRepository {
  String category = '技能講習';
  int writes = 0;
  @override
  Future<Map<String, dynamic>> loadAll() async => {
    'masters': [{'id': 'm', 'name': '資格A', 'category': category}, {'id': 'unused', 'name': '未登録資格'}],
    'workers': [{'id': 'w', 'name': '作業員A'}],
    'qualifications': [{'id': 'q', 'worker_id': 'w', 'qualification_master_id': 'm', 'issued_at': '2026-01-02'}],
  };
  @override
  Future<bool> canManageMaster() async => true;
  @override
  Future<bool> canManageWorkerQualifications() async => true;
  @override
  Future<void> updateMasterCategory(String masterId, String newCategory) async {
    expect(masterId, 'm');
    writes++;
    category = newCategory;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class _Certificates implements QualificationCertificateRepository {
  @override
  Future<bool> canManageCertificates() async => false;
  @override
  String? get currentUserId => 'actor';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
void main() {
  testWidgets('registered qualification shows date and category and edits refresh the list', (tester) async {
    final repository = _Repository();
    await tester.pumpWidget(MaterialApp(home: QualificationCloudPage(
      repository: repository, certificateRepository: _Certificates())));
    await tester.pumpAndSettle();
    expect(find.text('未登録資格'), findsNothing);
    expect(find.textContaining('取得日 2026-01-02'), findsOneWidget);
    expect(find.textContaining('区分 技能講習'), findsOneWidget);
    await tester.tap(find.text('詳細を確認'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('資格区分を変更'));
    await tester.pumpAndSettle();
    expect(find.text('同じ資格を持つ全員の区分に反映されます。'), findsOneWidget);
    await tester.tap(find.text('国家資格').last);
    await tester.pumpAndSettle();
    expect(repository.writes, 1);
    expect(find.textContaining('区分 国家資格'), findsOneWidget);
  });
}
