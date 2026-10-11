import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/people/employee_personnel_detail_page.dart';
import 'package:sk_works/features/people/people_page.dart';
import 'package:sk_works/features/people/personnel_family_member.dart';

void main() {
  final record = PersonRecord(
    id: 'worker',
    kind: PersonKind.employee,
    name: '社員名',
    familyComposition: '3人',
    familyMembers: [
      PersonnelFamilyMember(
        name: '家族氏名',
        relation: '子',
        birthDate: DateTime(2020, 1, 2),
        isDependent: true,
      ),
    ],
  );
  testWidgets(
    'viewer sees shared family table without write or output controls at narrow width',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: EmployeePersonnelDetailPage(
            record: record,
            allEmployees: [record],
            companyName: '会社',
            canManage: false,
            canViewFamily: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('顔写真未登録'), findsOneWidget);
      expect(find.byType(Table), findsWidgets);
      await tester.scrollUntilVisible(find.text('家族氏名'), 200);
      expect(find.text('2020/01/02'), findsOneWidget);
      expect(find.text('あり'), findsOneWidget);
      expect(find.text('編集'), findsNothing);
      expect(find.text('送信'), findsNothing);
      expect(find.text('印刷'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('without family permission sensitive family content is absent', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: EmployeePersonnelDetailPage(
          record: record,
          allEmployees: [record],
          companyName: '会社',
          canManage: false,
          canViewFamily: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(find.text('家族氏名'), findsNothing);
    expect(find.text('家族・扶養情報'), findsNothing);
  });
  testWidgets('portrait loading failure is distinct from missing photo', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: EmployeePersonnelDetailPage(
          record: record,
          allEmployees: [record],
          companyName: '会社',
          canManage: false,
          canViewFamily: true,
          portraitLoader: () async => throw StateError('offline'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('顔写真を取得できません'), findsOneWidget);
    expect(find.text('顔写真未登録'), findsNothing);
  });
}
