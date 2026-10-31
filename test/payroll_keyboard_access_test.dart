import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/payroll_keyboard_access.dart';

void main() {
  testWidgets('blank space closes keyboard without clearing input', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(home: PayrollKeyboardDismissArea(
      child: Scaffold(body: Column(children: [
        TextField(controller: controller),
        const Expanded(child: SizedBox(key: ValueKey('blank'))),
      ])),
    )));
    await tester.enterText(find.byType(TextField), '123');
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.tap(find.byKey(const ValueKey('blank')));
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);
    expect(controller.text, '123');
  });
}
