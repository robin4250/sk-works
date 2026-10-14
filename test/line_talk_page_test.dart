import 'support/line_test_app.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/chat/line_talk_page.dart';

void main() {
  test('public talk entry stays available independently of optional imports', () {
    final app = File('lib/app_v2.dart').readAsStringSync();
    expect(app, isNot(contains("'line_talk' || 'today_line' || 'line_history' => 'line_bridge'")));
    expect(app, contains("key: 'line_talk'"));
  });

  testWidgets('LINE talk requires a real signed-in backend and never fabricates saved posts', (tester) async {
    await tester.pumpWidget(const LineTestApp(home: LineTalkPage()));
    await tester.pump();
    expect(find.text('LINEトーク'), findsOneWidget);
    expect(find.text('SKOへのログインが必要です。'), findsOneWidget);
    expect(find.text('LINEグループを連携'), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('stage one help describes binding, text scope, and no attendance or invoice import', (tester) async {
    await tester.pumpWidget(const LineTestApp(home: LineTalkPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('使い方'));
    await tester.pumpAndSettle();
    expect(find.text('LINEトークの使い方'), findsOneWidget);
    expect(find.textContaining('期限内に連携文を送信'), findsOneWidget);
    expect(find.textContaining('出勤表・請求書への取込はまだ行いません'), findsOneWidget);
    expect(find.textContaining('停止中や連携前の過去投稿は自動では取得されません'), findsOneWidget);
    await tester.tap(find.text('閉じる'));
    await tester.pumpAndSettle();
    expect(find.text('LINEトークの使い方'), findsNothing);
  });
}
