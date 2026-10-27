import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/qualifications/qualification_cloud_page.dart';
import 'package:sk_works/features/qualifications/qualification_cloud_repository.dart';
import 'package:sk_works/features/qualifications/qualification_certificate_repository.dart';

class _Repository implements QualificationCloudRepository {
  _Repository(this.allowed);
  final bool allowed;
  int deletes = 0;
  @override
  Future<Map<String, dynamic>> loadAll() async => {
    'masters': [{'id': 'm', 'name': '資格A', 'category': '技能講習'}],
    'workers': [{'id': 'w', 'name': '作業員A'}],
    'qualifications': [{'id': 'q', 'worker_id': 'w', 'qualification_master_id': 'm', 'issued_at': '2026-01-02'}],
  };
  @override
  Future<bool> canManageMaster() async => false;
  @override
  Future<bool> canManageWorkerQualifications() async => allowed;
  @override
  Future<void> deleteMaster(String id) async { deletes++; }
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
  testWidgets('manager confirms master deletion', (tester) async {
    final repo = _Repository(true);
    await tester.pumpWidget(MaterialApp(home: QualificationCloudPage(repository: repo, certificateRepository: _Certificates())));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('資格マスター管理'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('削除'));
    await tester.pumpAndSettle();
    expect(find.text('登録済みの資格に使われている場合は削除できません。'), findsOneWidget);
    await tester.tap(find.text('削除').last);
    await tester.pumpAndSettle();
    expect(repo.deletes, 1);
  });
  testWidgets('viewer cannot open management', (tester) async {
    final repo = _Repository(false);
    await tester.pumpWidget(MaterialApp(home: QualificationCloudPage(repository: repo, certificateRepository: _Certificates())));
    await tester.pumpAndSettle();
    final button = tester.widget<IconButton>(find.byTooltip('資格マスター管理'));
    expect(button.onPressed, isNull);
  });
}
