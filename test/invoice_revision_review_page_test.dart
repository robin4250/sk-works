import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/invoices/invoice_revision_review_page.dart';

void main() {
  Map<String, dynamic> synthetic() => {
    'status': 'review_only', 'grand_total': 120000,
    'proposed_snapshot': <String, dynamic>{'sites': <Map<String, dynamic>>[
      <String, dynamic>{'site_name': '合成現場', 'lines': <Map<String, dynamic>>[
        <String, dynamic>{'work_content': '日勤', 'quantity': 6, 'amount': 90000},
        <String, dynamic>{'work_content': '残業', 'quantity': 1, 'amount': 3000},
        <String, dynamic>{'work_content': '共通手当', 'quantity': 2, 'amount': 6000},
      ]},
      <String, dynamic>{'site_name': '合成ルート', 'lines': <Map<String, dynamic>>[
        <String, dynamic>{'work_content': '複数現場', 'quantity': 1, 'amount': 21000},
      ]},
    ]},
  };

  testWidgets('review shows original calculation lines with no issue/share controls', (t) async {
    t.view.physicalSize = const Size(320, 568); t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize); addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(MaterialApp(home: InvoiceRevisionReviewPage(review: synthetic())));
    expect(find.textContaining('訂正案・未発行'), findsOneWidget);
    expect(find.text('数量 6'), findsOneWidget);
    await t.scrollUntilVisible(find.text('合成ルート'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('数量 1'), findsWidgets);
    await t.scrollUntilVisible(find.text('訂正案の請求金額'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('120,000円'), findsOneWidget);
    expect(find.text('発行'), findsNothing);
    expect(find.text('保存・共有'), findsNothing);
    expect(find.text('承認'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('unverified input and old seal are not rendered as a revision', (t) async {
    final data = synthetic();
    (data['proposed_snapshot'] as Map<String, dynamic>)['company_seal_snapshot'] = {'value': 'synthetic'};
    await t.pumpWidget(MaterialApp(home: InvoiceRevisionReviewPage(review: data)));
    expect(find.textContaining('訂正案を確認できません'), findsOneWidget);
    expect(find.text('120,000円'), findsNothing);
    expect(find.textContaining('合成現場'), findsNothing);
  });

  testWidgets('malformed calculation is held instead of showing a guessed amount', (t) async {
    final data = synthetic();
    final snapshot = data['proposed_snapshot'] as Map<String, dynamic>;
    final site = (snapshot['sites'] as List).first as Map<String, dynamic>;
    ((site['lines'] as List).first as Map<String, dynamic>)['amount'] = null;
    await t.pumpWidget(MaterialApp(home: InvoiceRevisionReviewPage(review: data)));
    expect(find.textContaining('内訳を確認できません'), findsOneWidget);
    expect(find.text('90,000円'), findsNothing);
  });
}
