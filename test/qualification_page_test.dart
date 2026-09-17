import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/qualifications/qualification_page.dart';

void main() {
  testWidgets('qualification page shows held qualifications', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: QualificationPage()),
    );

    expect(find.text('職長・安全衛生責任者'), findsOneWidget);
    expect(find.text('玉掛け技能講習'), findsOneWidget);
    expect(find.text('資格登録'), findsOneWidget);
  });

  testWidgets('qualification search filters records', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: QualificationPage()),
    );

    await tester.enterText(find.byType(TextField), '玉掛け');
    await tester.pump();

    expect(find.text('玉掛け技能講習'), findsOneWidget);
    expect(find.text('職長・安全衛生責任者'), findsNothing);
  });
}
