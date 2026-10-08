import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/attendance/group_checkout_dialog.dart';
import 'package:sk_works/features/attendance/group_checkout_repository.dart';

class RetryRepository extends GroupCheckoutRepository {
  RetryRepository(SupabaseClient client) : super(client);
  final List<GroupCheckoutRequest> requests = [];
  @override
  Future<void> commit(GroupCheckoutRequest request) async {
    requests.add(request);
    if (requests.length == 1) {
      throw StateError('通信失敗');
    }
  }
}

void main() {
  testWidgets('uncertain send retries identical token and leaves early checkout unselected', (tester) async {
    final client = SupabaseClient('https://example.invalid', 'test-anon',
      authOptions: const AuthClientOptions(autoRefreshToken: false));
    addTearDown(client.dispose);
    final repository = RetryRepository(client);
    final date = DateTime(2026, 10, 31);
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => TextButton(
      onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => GroupCheckoutPage(
      repository: repository, anchorId: 'anchor', workDate: date,
      initialCandidates: [
        GroupCheckoutCandidate(sourceId: 'pending', workerId: 'one', name: '一人目', workDate: date),
        GroupCheckoutCandidate(sourceId: 'early', workerId: 'two', name: '二人目', workDate: date,
          clockOutAt: DateTime(2026, 10, 31, 23)),
      ],
    ))), child: const Text('開く')))));
    await tester.tap(find.text('開く'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('選択したメンバーを代理退勤'));
    await tester.pumpAndSettle();
    expect(find.text('同じ内容で再確認'), findsOneWidget);
    final checkboxes = tester.widgetList<CheckboxListTile>(find.byType(CheckboxListTile)).toList();
    expect(checkboxes.every((box) => box.onChanged == null), isTrue);
    expect(repository.requests.single.sourceIds, ['pending']);
    await tester.tap(find.text('同じ内容で再確認'));
    await tester.pumpAndSettle();
    expect(repository.requests.length, 2);
    expect(repository.requests.last.token, repository.requests.first.token);
  });
}
