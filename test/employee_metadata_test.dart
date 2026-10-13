import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/people/people_page.dart';
import 'package:sk_works/features/people/people_cloud_repository.dart';
import 'package:sk_works/features/people/employee_personnel_edit_page.dart';

void main() {
  test('employee metadata survives JSON round trip without changing existing fields', () {
    const record = PersonRecord(
      id: 'worker-1',
      kind: PersonKind.employee,
      name: '山田太郎',
      employeeNumber: 'aB-0007',
      department: '工事部',
      role: '鳶工',
      hireDate: '2020-04-01',
      phone: '09012345678',
    );
    final restored = PersonRecord.fromJson(
      Map<String, dynamic>.from(record.toJson()),
    );
    expect(restored.employeeNumber, 'aB-0007');
    expect(restored.department, '工事部');
    expect(restored.role, '鳶工');
    expect(restored.hireDate, '2020-04-01');
    expect(restored.phone, '09012345678');
    final oldRecord = PersonRecord.fromJson({
      'id': 'old',
      'name': '既存社員',
      'role': '職長',
    });
    expect(oldRecord.employeeNumber, isEmpty);
    expect(oldRecord.department, isEmpty);
    expect(oldRecord.hireDate, isEmpty);
    expect(oldRecord.role, '職長');
  });
  test('employee metadata rejects invalid dates and multiline numbers before saving', () {
    expect(
      () => PeopleCloudRepository.validatePersonnelMetadata({
        'employeeNumber': '',
        'hireDate': '',
      }),
      returnsNormally,
    );
    expect(
      () => PeopleCloudRepository.validatePersonnelMetadata({
        'employeeNumber': 'A-007',
        'hireDate': '2024-02-29',
      }),
      returnsNormally,
    );
    expect(
      () => PeopleCloudRepository.validatePersonnelMetadata({
        'hireDate': '2025-02-29',
      }),
      throwsStateError,
    );
    expect(
      () => PeopleCloudRepository.validatePersonnelMetadata({
        'employeeNumber': 'A\n007',
      }),
      throwsStateError,
    );
  });
  test('employee number conflicts have a friendly message without masking other duplicate errors', () {
    const duplicateNumber = PostgrestException(
      message: 'employee_number_duplicate',
      code: '23505',
    );
    expect(
      PeopleCloudRepository.personnelSaveError(duplicateNumber),
      contains('同じ会社で使用されています'),
    );
    const duplicatePhone = PostgrestException(
      message: 'duplicate phone',
      code: '23505',
    );
    expect(
      PeopleCloudRepository.personnelSaveError(duplicatePhone),
      isNot(contains('社員番号')),
    );
  });
  testWidgets(
    'employee editing exposes saved number department and editable hire date',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: EmployeePersonnelEditPage(
            record: PersonRecord(
              id: 'w',
              kind: PersonKind.employee,
              name: '社員',
              employeeNumber: '0007',
              department: '工事部',
              role: '鳶工',
              hireDate: '2020-04-01',
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('社員番号'), findsOneWidget);
      expect(find.text('所属'), findsOneWidget);
      expect(find.text('入社日'), findsOneWidget);
      expect(find.text('2020/04/01'), findsOneWidget);
      await tester.tap(find.byTooltip('入社日を未登録に戻す'));
      await tester.pump();
      expect(find.text('2020/04/01'), findsNothing);
      expect(
        find.descendant(
          of: find.widgetWithText(ListTile, '入社日'),
          matching: find.text('未登録'),
        ),
        findsOneWidget,
      );
    },
  );
}
