import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sk_works/features/companies/trade_company_dialog.dart';

void main() {
  testWidgets(
    'company actions have equal width height spacing and keep callbacks',
    (tester) async {
      var selected = '';
      final labels = ['閉じる', '削除', '会社情報を編集', '計算元を確認・変更', '契約設定'];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              child: TradeCompanyActionButtons(
                actions: [
                  for (final label in labels)
                    OutlinedButton(
                      onPressed: () => selected = label,
                      child: Text(label),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      final rects = [
        for (final label in labels)
          tester.getRect(find.widgetWithText(OutlinedButton, label)),
      ];
      for (var i = 0; i < rects.length; i++) {
        expect(rects[i].width, rects.first.width);
        expect(rects[i].height, rects.first.height);
        expect(rects[i].height, greaterThanOrEqualTo(48));
        if (i > 0) expect(rects[i].top - rects[i - 1].bottom, 8);
      }
      await tester.tap(find.text('契約設定'));
      expect(selected, '契約設定');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('small enlarged dialog scrolls to last action without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var saved = false;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: Scaffold(
          body: TradeCompanyDialog(
            title: const Text('会社情報'),
            content: const Text('会社の住所と電話番号などの情報'),
            actions: [
              for (var i = 0; i < 5; i++)
                TextButton(onPressed: () {}, child: Text('操作$i')),
              FilledButton(
                onPressed: () => saved = true,
                child: const Text('保存'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.scrollUntilVisible(
      find.text('保存'),
      100,
      scrollable: find
          .descendant(
            of: find.byType(TradeCompanyDialog),
            matching: find.byType(Scrollable),
          )
          .last,
    );
    await tester.tap(find.text('保存'));
    expect(saved, isTrue);
    expect(tester.takeException(), isNull);
  });
}
