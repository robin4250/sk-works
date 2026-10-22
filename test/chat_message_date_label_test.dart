import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/chat/chat_message_date_label.dart';
import 'package:sk_works/features/chat/line_received_messages_list.dart';

void main() {
  final now = DateTime(2026, 10, 22, 12);

  test('dates omit today and retain the necessary calendar context', () {
    expect(chatMessageDateLabel('2026-10-22T00:01:00', now: now), '');
    expect(chatMessageDateLabel('2026-10-21T23:59:00', now: now), '21日');
    expect(chatMessageDateLabel('2026-09-30T12:00:00', now: now), '9月30日');
    expect(chatMessageDateLabel('2025-10-22T12:00:00', now: now), '2025年10月22日');
    expect(chatMessageDateLabel('2027-01-01T12:00:00', now: now), '2027年1月1日');
  });

  test('invalid timestamps are omitted and offset timestamps use local dates', () {
    expect(chatMessageDateLabel(null, now: now), '');
    expect(chatMessageDateLabel('not a timestamp', now: now), '');
    final local = DateTime(2026, 10, 21, 23, 59);
    expect(chatMessageDateLabel(local.toUtc().toIso8601String(), now: now), '21日');
    expect(chatMessageDateLabel('2026-10-22T00:30:00+14:00',
      now: DateTime.parse('2026-10-21T10:30:00Z')), '');
  });

  test('year and month boundaries keep distinguishable dates', () {
    expect(chatMessageDateLabel('2025-12-31T23:59:00',
      now: DateTime(2026, 1, 1)), '2025年12月31日');
    expect(chatMessageDateLabel('2026-02-28T23:59:00',
      now: DateTime(2026, 3, 1)), '2月28日');
  });

  testWidgets('date uses small text and today reserves no date space', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      ChatMessageDateLabel(sentAt: '2026-10-21T12:00:00', now: now))));
    expect(tester.widget<Text>(find.text('21日')).style?.fontSize, 10);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      ChatMessageDateLabel(sentAt: '2026-10-22T12:00:00', now: now))));
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('LINE date sits above the card while time remains with sender', (tester) async {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final timestamp = DateTime(yesterday.year, yesterday.month, yesterday.day, 12, 34);
    final date = chatMessageDateLabel(timestamp.toIso8601String());
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      LineReceivedMessagesList(rows: [{
        'sender_display_name': 'Sender', 'body': 'Message',
        'sent_at': timestamp.toIso8601String(),
      }]))));
    expect(find.text(date), findsOneWidget);
    expect(find.text('Sender  12:34'), findsOneWidget);
    expect(tester.getTopLeft(find.text(date)).dy,
      lessThan(tester.getTopLeft(find.byType(Card)).dy));
    expect(find.text('Message'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
