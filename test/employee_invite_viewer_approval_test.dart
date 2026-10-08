import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/people/employee_invite_page.dart';
import 'package:sk_works/international/language_controller.dart';
import 'package:sk_works/international/language_pack_registry.dart';

void main() {
  testWidgets('approval selection preserves viewer role and survives management deselection', (tester) async {
    SkoLanguageController.pack.value = LanguagePackRegistry.resolve('ja');
    await tester.pumpWidget(const MaterialApp(
      home: EmployeeInvitePage(canAssignManagementRole: true),
    ));
    await tester.pumpAndSettle();
    final approval = find.widgetWithText(CheckboxListTile, '承認担当者にする');
    final manager = find.widgetWithText(CheckboxListTile, 'サブ管理者にする');
    await tester.ensureVisible(approval);
    await tester.tap(approval);
    await tester.pumpAndSettle();
    expect(tester.widget<CheckboxListTile>(approval).value, isTrue);
    expect(tester.widget<CheckboxListTile>(manager).value, isFalse);
    await tester.ensureVisible(manager);
    await tester.tap(manager);
    await tester.pumpAndSettle();
    await tester.tap(manager);
    await tester.pumpAndSettle();
    expect(tester.widget<CheckboxListTile>(manager).value, isFalse);
    expect(tester.widget<CheckboxListTile>(approval).value, isTrue);
  });

  testWidgets('ordinary caller has no role or approval assignment controls', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: EmployeeInvitePage()));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(CheckboxListTile, '承認担当者にする'), findsNothing);
    expect(find.widgetWithText(CheckboxListTile, 'サブ管理者にする'), findsNothing);
  });
}
