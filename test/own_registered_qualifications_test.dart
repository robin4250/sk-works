import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/qualifications/own_qualification_registration_page.dart';
import 'package:sk_works/features/qualifications/qualification_cloud_repository.dart';

class _Repository implements QualificationCloudRepository {
  _Repository(this.rows);
  final List<Map<String, dynamic>> rows;
  @override
  String? get currentUserId => 'actor';
  @override
  Future<Map<String, dynamic>> loadOwnQualificationWorkspace() async => {
    'worker': {'id': 'worker', 'name': '作業員'},
    'masters': [
      {'id': 'saved', 'name': '取得済み資格', 'category': '国家資格'},
      {'id': 'empty', 'name': '未取得資格', 'category': '技能講習'},
    ],
    'qualifications': rows,
  };
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('登録資格のみ表示し資格日は区分と並べる', (tester) async {
    final repository = _Repository([
      {'id': 'one', 'worker_id': 'worker', 'qualification_master_id': 'saved',
       'issued_at': '2024-04-01', 'attachment_path': null,
       'attachment_back_path': null},
    ]);
    await tester.pumpWidget(MaterialApp(home: OwnQualificationRegistrationPage(repository: repository)));
    await tester.pumpAndSettle();
    expect(find.text('取得済み資格'), findsOneWidget);
    expect(find.text('未取得資格'), findsNothing);
    expect(find.textContaining('取得日 2024-04-01 / 国家資格'), findsOneWidget);
    expect(find.text('資格を登録'), findsOneWidget);
  });

  testWidgets('保有資格がない場合も登録操作は使用できる', (tester) async {
    await tester.pumpWidget(MaterialApp(home: OwnQualificationRegistrationPage(repository: _Repository([]))));
    await tester.pumpAndSettle();
    expect(find.text('未取得資格'), findsNothing);
    expect(find.text('取得済み資格'), findsNothing);
    await tester.tap(find.text('資格を登録'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    expect(find.text('未取得資格'), findsWidgets);
  });
}
