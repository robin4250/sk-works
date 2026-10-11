import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sk_works/features/people/employee_initial_registration_page.dart';
import 'package:sk_works/features/people/employee_registration_page.dart';

void main() {
  testWidgets('registration-only access does not expose invitation or URL controls', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: EmployeeRegistrationPage(allowInvitations: false),
    ));
    await tester.pumpAndSettle();
    expect(find.text('登録だけ'), findsOneWidget);
    expect(find.text('登録して続けて案内作成'), findsNothing);
    expect(find.text('TestFlight URL'), findsNothing);
    expect(find.text('未送信・状態未確認の人だけ表示'), findsNothing);
    expect(find.byIcon(Icons.refresh), findsNothing);
    await tester.tap(find.byIcon(Icons.help_outline));
    await tester.pumpAndSettle();
    expect(find.text('従業員登録・初回案内'), findsOneWidget);
    await tester.tap(find.text('確認'));
    await tester.pumpAndSettle();
    expect(find.text('従業員登録・初回案内'), findsNothing);
  });

  testWidgets('administrator entry keeps registration and distribution URL on the same page', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: EmployeeInitialRegistrationPage()));
    await tester.pumpAndSettle();
    expect(find.text('登録だけ'), findsOneWidget);
    expect(find.text('登録して続けて案内作成'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('URLを保存'),
      250,
      scrollable: find.descendant(
        of: find.byType(ListView), matching: find.byType(Scrollable),
      ).first,
    );
    expect(find.text('TestFlight URL'), findsOneWidget);
    expect(find.text('URLを保存'), findsOneWidget);
    expect(find.text('従業員登録'), findsOneWidget);
  });
}
