import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/daily_reports/signature_capture_page.dart';

void main() {
  testWidgets(
    'member selection stays editable and returns actual signed name',
    (tester) async {
      SignatureResult? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await Navigator.of(context).push<SignatureResult>(
                    MaterialPageRoute(
                      builder: (_) => const SignatureCapturePage(
                        initialSignerName: '保存済み報告者',
                        signerNameOptions: ['田中', '佐藤', '田中', ''],
                      ),
                    ),
                  );
                },
                child: const Text('開く'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('開く'));
      await tester.pumpAndSettle();
      expect(find.text('保存済み報告者'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('signature-member-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('佐藤').last);
      await tester.pumpAndSettle();
      expect(find.text('佐藤'), findsWidgets);
      await tester.enterText(find.byType(TextField), '  佐藤 太郎  ');
      final canvas = find.byWidgetPredicate(
      (widget) => widget is GestureDetector && widget.onPanStart != null,
    );
      await tester.dragFrom(tester.getCenter(canvas), const Offset(80, 30));
      await tester.pump();
      await tester.tap(find.text('このサインで確定'));
      await tester.pumpAndSettle();
      expect(result?.signerName, '佐藤 太郎');
      expect(result?.strokes, isNotEmpty);
    },
  );

  testWidgets(
    'registered responsible name is editable; missing name requires entry',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SignatureCapturePage(initialSignerName: '登録責任者'),
        ),
      );
      expect(find.text('登録責任者'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('signature-member-picker')),
        findsNothing,
      );
      await tester.enterText(find.byType(TextField), '');
      await tester.tap(find.text('このサインで確定'));
      await tester.pump();
      expect(find.text('現場責任者名を入力してください'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '変更責任者');
      expect(find.text('変更責任者'), findsOneWidget);
    },
  );
}
