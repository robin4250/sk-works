import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/chat/line_received_messages_list.dart';

void main() {
  testWidgets('received LINE opens at newest and retains older source posts', (tester) async {
    final rows = List.generate(250, (i) => <String, dynamic>{
      'id': '$i', 'body': 'post $i', 'sender_display_name': 'Sender',
      'sent_at': DateTime.utc(2026, 10, 13).add(Duration(minutes: i)).toIso8601String(),
    });
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: LineReceivedMessagesList(rows: rows))));
    expect(find.text('post 249'), findsOneWidget);
    expect(find.text('post 0'), findsNothing);
    final latestTop = tester.getTopLeft(find.text('post 249')).dy;
    expect(tester.getTopLeft(find.text('post 248')).dy, lessThan(latestTop));
    await tester.scrollUntilVisible(find.text('post 0'), 500,
      scrollable: find.byWidgetPredicate((widget) => widget is Scrollable &&
        widget.axisDirection == AxisDirection.up), maxScrolls: 100);
    expect(find.text('post 0'), findsOneWidget);
    expect(rows.first['body'], 'post 0');
    expect(rows.last['body'], 'post 249');
  });

  testWidgets('newly received post remains at the latest end after refresh', (tester) async {
    Future<void> render(List<Map<String, dynamic>> rows) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(
        body: LineReceivedMessagesList(rows: rows))));
      await tester.pump();
    }
    await render([{'body': 'old', 'sender_display_name': 'LINE'}]);
    await render([{'body': 'old', 'sender_display_name': 'LINE'},
      {'body': 'new', 'sender_display_name': 'LINE'}]);
    expect(find.text('new'), findsOneWidget);
    expect(tester.getTopLeft(find.text('old')).dy,
      lessThan(tester.getTopLeft(find.text('new')).dy));
  });
}
