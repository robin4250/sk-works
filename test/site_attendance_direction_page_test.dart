import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/sites/site_attendance_direction_page.dart';
import 'package:sk_works/features/sites/site_cloud_repository.dart';

class _Repository implements SiteCloudRepository {
  _Repository(this.row);

  final Map<String, dynamic> row;
  final actions = <String>[];
  @override
  String? attendanceDirectionSession = 'fixture-session';

  @override
  Future<List<Map<String, dynamic>>> attendanceDirectionWorkspace({
    required String siteId,
    required String sessionToken,
    String? itemId,
    String? action,
    String? requestId,
  }) async {
    if (siteId != 'east' || sessionToken != 'fixture-session') {
      throw StateError('Unexpected site or session');
    }
    if (action != null) {
      if (itemId != 'east-link') throw StateError('Unexpected site link');
      actions.add(action);
      if (action == 'send') {
        row.addAll({
          'request_id': 'request-1',
          'requested_by_us': true,
          'requested_direction': 'send',
        });
      } else if (action == 'approve') {
        if (requestId != 'request-1') throw StateError('Unexpected request');
        row['direction'] = 'send';
        row.remove('request_id');
      }
    }
    return [Map.of(row)];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Future<void> open(WidgetTester tester, _Repository repo) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SiteAttendanceDirectionPage(
          siteId: 'east',
          siteName: '東現場',
          siteAddress: '現場住所',
          repository: repo,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Map<String, dynamic> fixture() => {
    'item_id': 'east-link',
    'company_name': 'A社',
    'other_site': '東現場',
    'default_role': 'customer',
    'trade_company_id': 'company-a',
    'can_send': true,
    'can_receive': true,
  };

  testWidgets(
    'approved company direction preselects the directory default without sharing',
    (tester) async {
      final repo = _Repository(fixture());
      await open(tester, repo);
      expect(
        tester
            .widget<DropdownButton<String>>(find.byType(DropdownButton<String>))
            .value,
        'send',
      );
      expect(repo.actions, isEmpty);
      expect(find.text('注文請書生成'), findsNothing);
      await tester.tap(find.text('相手に申請する'));
      await tester.pumpAndSettle();
      expect(repo.actions, ['send']);
      expect(find.textContaining('相手の承認待ち'), findsOneWidget);
      expect(find.text('注文請書生成'), findsNothing);
    },
  );

  testWidgets(
    'counterparty approval switches the document entry to the saved role',
    (tester) async {
      final repo = _Repository(
        fixture()..addAll({
          'direction': 'receive',
          'request_id': 'request-1',
          'requested_by_us': false,
          'requested_direction': 'send',
        }),
      );
      await open(tester, repo);
      expect(find.text('注文書生成'), findsOneWidget);
      expect(find.text('注文請書生成'), findsNothing);
      await tester.tap(find.text('承認'));
      await tester.pumpAndSettle();
      expect(repo.actions, ['approve']);
      expect(find.text('注文書生成'), findsNothing);
      expect(find.text('注文請書生成'), findsOneWidget);
    },
  );
}
