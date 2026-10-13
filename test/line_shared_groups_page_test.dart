import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/chat/line_shared_groups_page.dart';
import 'package:sk_works/features/chat/line_shared_groups_repository.dart';

class FakeGroups extends LineSharedGroupsRepository {
  FakeGroups(this.rows, {this.fail = false})
    : super(SupabaseClient('https://example.invalid', 'public-test'));
  final List<Map<String, dynamic>> rows;
  final bool fail;
  @override
  Future<List<Map<String, dynamic>>> groups() async {
    if (fail) throw StateError('metadata unavailable');
    return rows;
  }
}

void main() {
  testWidgets(
    'LINE and SKO origins open the same canonical group without duplicating rows',
    (tester) async {
      String? opened;
      await tester.pumpWidget(
        MaterialApp(
          home: LineSharedGroupsPage(
            repository: FakeGroups([
              {'group_id': 'shared', 'name': 'Shared group', 'origin': 'sko'},
              {'group_id': 'line-only', 'name': 'LINE group', 'origin': 'line'},
            ]),
            onOpenGroup: (id) async {
              opened = id;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Shared group'), findsOneWidget);
      expect(find.text('LINE group'), findsOneWidget);
      await tester.tap(find.text('Shared group'));
      expect(opened, 'shared');
    },
  );
  testWidgets(
    'metadata failure shows error and does not silently present a legacy list',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: LineSharedGroupsPage(
            repository: FakeGroups([], fail: true),
            onOpenGroup: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('グループを読み込めませんでした。再読み込みしてください。'), findsOneWidget);
      expect(find.byType(ListTile), findsNothing);
    },
  );
}
