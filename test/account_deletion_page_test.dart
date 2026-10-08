import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/account_deletion/account_deletion_page.dart';
import 'package:sk_works/features/account_deletion/account_deletion_status.dart';

void main() {
  testWidgets('disabled intake only permits read-only reload and preserves pending status', (tester) async {
    var reads = 0;
    await tester.pumpWidget(MaterialApp(home: AccountDeletionPage(loadStatus: () async {
      reads++;
      return const AccountDeletionStatus(AccountDeletionState.requested);
    })));
    await tester.pumpAndSettle();
    expect(find.text('アカウント削除の受付は現在停止しています。'), findsOneWidget);
    expect(find.text('削除申請受付済み（削除未完了）'), findsOneWidget);
    expect(find.byType(OutlinedButton), findsOneWidget);
    await tester.tap(find.byType(OutlinedButton));
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(find.text('削除処理完了'), findsNothing);
  });
  testWidgets('status failure is not displayed as no request or completion', (tester) async {
    await tester.pumpWidget(MaterialApp(home: AccountDeletionPage(loadStatus: () async {
      throw StateError('private_error_fixture');
    })));
    await tester.pumpAndSettle();
    expect(find.text('削除申請の状態を確認できません'), findsOneWidget);
    expect(find.textContaining('private_error_fixture'), findsNothing);
    expect(find.text('削除申請はありません'), findsNothing);
  });
}
