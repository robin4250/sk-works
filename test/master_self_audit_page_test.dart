import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/features/security/master_self_audit_page.dart';
import '../lib/features/security/master_self_audit_repository.dart';
import '../lib/features/security/master_self_operation_audit.dart';

void main() {
  testWidgets(
    'separates real operation audit from empty auth storage and explains limits',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MasterSelfAuditPage(
            loadRecords: () async => MasterSelfAuditSnapshot(
              cutoff: DateTime.utc(2026, 10, 14, 1),
              operations: [
                MasterSelfOperationAuditEvent(
                  action: 'master_device_bootstrap',
                  at: DateTime.utc(2026, 10, 14),
                ),
              ],
              authentication: const [],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('最初のマスター端末を登録'), findsOneWidget);
      expect(find.text('本人の認証'), findsOneWidget);
      expect(find.textContaining('安全・未発生を意味しません'), findsOneWidget);
      await tester.tap(find.byTooltip('ヘルプ'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Write audit logs to the database'),
        findsOneWidget,
      );
    },
  );
  testWidgets('failure does not claim an empty audit', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MasterSelfAuditPage(
          loadRecords: () async => throw StateError('private backend detail'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('記録を取得できません'), findsOneWidget);
    expect(find.textContaining('private backend detail'), findsNothing);
    expect(find.textContaining('表示できる保存記録'), findsNothing);
  });
}
