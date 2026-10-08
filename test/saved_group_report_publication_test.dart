import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/notifications/saved_group_report_publication.dart';

void main() {
  test('failed or partially attached save never publishes', () async {
    final published = <String>[];
    await expectLater(registerSavedGroupReport(notificationEligible: true,
      save: () async => throw StateError('evidence attachment failed'),
      publish: (id) async { published.add(id); }), throwsStateError);
    expect(await registerSavedGroupReport(notificationEligible: true,
      save: () async => null,
      publish: (id) async { published.add(id); }), isNull);
    expect(published, isEmpty);
  });
  test('explicit registration publishes fixed saved ID only when eligible', () async {
    final published = <String>[];
    expect(await registerSavedGroupReport(notificationEligible: false,
      save: () async => 'draft-report',
      publish: (id) async { published.add(id); }), 'draft-report');
    expect(published, isEmpty);
    var currentSelection = 'saved-report';
    expect(await registerSavedGroupReport(notificationEligible: true,
      save: () async => currentSelection,
      publish: (id) async {
        currentSelection = 'different-report';
        published.add(id);
      }), 'saved-report');
    expect(published, ['saved-report']);
    expect(currentSelection, 'different-report');
  });
  test('only a complete actual site group roster is eligible', () {
    final clockOut = DateTime(2026, 10, 9, 17);
    bool eligible({String? anchor = 'source', String? site = 'site', String? route,
      List<({String? sourceId, DateTime? clockOutAt})>? rows}) =>
      groupReportPublicationEligible(anchorSourceId: anchor, siteId: site,
        routeAssignmentId: route,
        roster: rows ?? [(sourceId: 'source', clockOutAt: clockOut)]);
    expect(eligible(), isTrue);
    expect(eligible(anchor: null), isFalse);
    expect(eligible(site: null), isFalse);
    expect(eligible(route: 'route'), isFalse);
    expect(eligible(rows: []), isFalse);
    expect(eligible(rows: [(sourceId: null, clockOutAt: clockOut)]), isFalse);
    expect(eligible(rows: [(sourceId: 'source', clockOutAt: null)]), isFalse);
    expect(eligible(rows: [(sourceId: 'source', clockOutAt: clockOut),
      (sourceId: null, clockOutAt: clockOut)]), isFalse);
  });
  test('OFF and duplicate publication return zero without claiming a failure', () async {
    for (final count in [0, 2]) {
      final ids = <String>[];
      expect(await publishSavedGroupReport('saved-report', invoke: (id) async {
        ids.add(id);
        return count;
      }), isTrue);
      expect(ids, ['saved-report']);
    }
  });
  test('unapplied staged publisher is unavailable', () async {
    for (final code in ['PGRST202', '42883']) {
      expect(await publishSavedGroupReport('saved-report', invoke: (_) async {
        throw PostgrestException(message: 'missing staged RPC', code: code);
      }), isFalse);
    }
  });
  test('unknown result retries only the same saved report ID', () async {
    final ids = <String>[];
    Future<dynamic> invoke(String id) async {
      ids.add(id);
      if (ids.length == 1) throw StateError('connection lost after server commit');
      return 0; // The durable server receipt prevents a second notification.
    }
    await expectLater(publishSavedGroupReport('fixed-saved-report', invoke: invoke),
      throwsStateError);
    expect(await publishSavedGroupReport('fixed-saved-report', invoke: invoke), isTrue);
    expect(ids, ['fixed-saved-report', 'fixed-saved-report']);
  });
  test('recipient/author denial and malformed response remain unconfirmed', () async {
    await expectLater(publishSavedGroupReport('report', invoke: (_) async {
      throw const PostgrestException(message: 'author required', code: '42501');
    }), throwsA(isA<PostgrestException>()));
    for (final invalid in [null, -1, '1', 1.5]) {
      await expectLater(publishSavedGroupReport('report', invoke: (_) async => invalid),
        throwsStateError);
    }
  });
}
