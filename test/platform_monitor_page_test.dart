import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/security/platform_monitor_page.dart';
import 'package:sk_works/features/security/platform_monitor_repository.dart';

Map<String, dynamic> report({List<Object?> events = const [], List<Object?> windows = const []}) => {
  'version': 1, 'source_provenance': 'supabase_platform_logs', 'scope': 'platform_operator',
  'retention_days': 7, 'coverage': 'bounded_queries_not_continuous_monitoring',
  'events': events, 'windows': windows,
};
void main() {
  test('real provenance and strict projection reject synthetic and extra private fields', () {
    expect(PlatformMonitorSnapshot.parse(report()).events, isEmpty);
    expect(() => PlatformMonitorSnapshot.parse({...report(), 'source_provenance': 'synthetic_fixture'}), throwsFormatException);
    expect(() => PlatformMonitorSnapshot.parse({...report(), 'raw_ip': 'private'}), throwsFormatException);
    expect(() => PlatformMonitorSnapshot.parse(report(events: [{'source': 'edge_logs', 'key_epoch': 1, 'event_key': 'a' * 64, 'occurred_at': '2026-10-16T10:00:00Z', 'result': 'blocked_attack', 'target_key': null, 'source_key': null, 'source_tracking': 'unavailable'}])), throwsFormatException);
  });
  testWidgets('not started is not presented as safe empty monitoring', (tester) async {
    await tester.pumpWidget(MaterialApp(home: PlatformMonitorPage(checkAvailable: () async => false)));
    await tester.pumpAndSettle();
    expect(find.textContaining('監視未開始'), findsOneWidget);
    expect(find.textContaining('保存対象の記録はありません'), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });
  testWidgets('capability errors do not downgrade to not started or empty', (tester) async {
    await tester.pumpWidget(MaterialApp(home: PlatformMonitorPage(checkAvailable: () async => throw StateError('secret'))));
    await tester.pumpAndSettle();
    expect(find.textContaining('接続・権限を確認できません'), findsOneWidget);
    expect(find.textContaining('監視未開始'), findsNothing);
    expect(find.textContaining('secret'), findsNothing);
  });
  testWidgets('proof read has single pending operation, clears password and displays coverage honestly', (tester) async {
    final pending = Completer<PlatformMonitorSnapshot>(); var calls = 0;
    await tester.pumpWidget(MaterialApp(home: PlatformMonitorPage(checkAvailable: () async => true, loadSnapshot: (password) { expect(password, 'fixture-password'); calls++; return pending.future; })));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'fixture-password');
    await tester.tap(find.text('再認証して記録を表示')); await tester.pump();
    expect(calls, 1); expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    pending.complete(PlatformMonitorSnapshot.parse(report())); await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
    expect(find.textContaining('監視が動作した証拠はまだありません'), findsOneWidget);
    expect(find.textContaining('安全性を証明しません'), findsOneWidget);
  });
  testWidgets('read permission failure is not an empty or inactive safe feed', (tester) async {
    await tester.pumpWidget(MaterialApp(home: PlatformMonitorPage(checkAvailable: () async => true, loadSnapshot: (_) async => throw StateError('secret'))));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'fixture-password');
    await tester.tap(find.text('再認証して記録を表示')); await tester.pumpAndSettle();
    expect(find.textContaining('監視記録を取得できません'), findsOneWidget);
    expect(find.textContaining('監視未開始'), findsNothing);
    expect(find.textContaining('保存対象の記録はありません'), findsNothing);
    expect(find.textContaining('secret'), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
  });
  testWidgets('OFF server is explicitly not started after proof attempt', (tester) async {
    await tester.pumpWidget(MaterialApp(home: PlatformMonitorPage(checkAvailable: () async => true, loadSnapshot: (_) async => throw PlatformMonitorUnavailable())));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'fixture-password');
    await tester.tap(find.text('再認証して記録を表示')); await tester.pumpAndSettle();
    expect(find.textContaining('監視未開始'), findsOneWidget);
    expect(find.textContaining('保存対象の記録はありません'), findsNothing);
  });
  testWidgets('late response after leaving does not reuse disposed password input', (tester) async {
    final pending = Completer<PlatformMonitorSnapshot>();
    await tester.pumpWidget(MaterialApp(home: PlatformMonitorPage(checkAvailable: () async => true, loadSnapshot: (_) => pending.future)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'fixture-password');
    await tester.tap(find.text('再認証して記録を表示')); await tester.pump();
    await tester.pumpWidget(const SizedBox());
    pending.complete(PlatformMonitorSnapshot.parse(report())); await tester.pump();
    expect(tester.takeException(), isNull);
  });

}
