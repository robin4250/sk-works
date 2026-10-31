import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/shared/financial_preview_chrome.dart';

void main() {
  for (final scale in [1.0, 1.5, 2.0]) {
    testWidgets(
      'portrait controls retain preview and tap targets at scale $scale',
      (tester) async {
        tester.view.physicalSize = const Size(430, 932);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var prints = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: const Size(430, 932),
                textScaler: TextScaler.linear(scale),
                padding: const EdgeInsets.only(top: 47, bottom: 34),
              ),
              child: Scaffold(
                appBar: AppBar(title: const Text('請求書')),
                body: FinancialPreviewChrome(
                  status: const [
                    Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('未確定の請書があります。内容と承認状態を確認してください。'),
                    ),
                  ],
                  actions: [
                    for (final label in [
                      '請書入力',
                      '請書保存・印刷',
                      '承認済み請書',
                      '承認履歴・印影設定',
                    ])
                      TextButton(onPressed: () {}, child: Text(label)),
                  ],
                  preview: const ColoredBox(color: Colors.white),
                  footer: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            prints++;
                          },
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 48),
                          ),
                          child: const Text('印刷'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          onPressed: () {},
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 48),
                          ),
                          child: const Text('保存・共有'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        final document = tester.getRect(
          find.byKey(const ValueKey('financial_preview_document_viewport')),
        );
        final body = tester.getSize(find.byType(FinancialPreviewChrome));
        expect(document.height, greaterThan(body.height * .48));
        expect(
          tester.getSize(find.widgetWithText(OutlinedButton, '印刷')).height,
          greaterThanOrEqualTo(48),
        );
        await tester.tap(find.widgetWithText(OutlinedButton, '印刷'));
        expect(prints, 1);
        await tester.drag(
          find.byKey(const ValueKey('financial_preview_controls_scroll')),
          const Offset(0, -350),
        );
        await tester.pumpAndSettle();
        expect(find.text('承認履歴・印影設定').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
