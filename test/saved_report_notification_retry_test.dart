import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/notifications/saved_report_notification_retry_store.dart';

void main() {
  const original = SavedReportNotificationRetry(userId: 'user-a', companyId: 'company-a', reportId: 'saved-id');
  test('actual store survives a new instance and separates user/company IDs', () async {
    final disk = <String, String>{};
    SavedReportNotificationRetryStore store() => SavedReportNotificationRetryStore(
      read: (key) async => disk[key], write: (key, value) async { disk[key] = value; });
    final first = store();
    const anotherCompany = SavedReportNotificationRetry(userId: 'user-a', companyId: 'company-b', reportId: 'another-id');
    const anotherUser = SavedReportNotificationRetry(userId: 'user-b', companyId: 'company-a', reportId: 'third-id');
    await Future.wait([first.remember(original), store().remember(anotherCompany), store().remember(anotherUser)]);
    final restored = store();
    expect((await restored.load('user-a')).map((value) => value.reportId), ['saved-id', 'another-id']);
    expect((await restored.load('user-b')).single.reportId, 'third-id');
    await restored.confirmed(original);
    expect((await store().load('user-a')).single.companyId, 'company-b');
    expect((await store().load('user-b')).single.reportId, 'third-id');
  });
  test('corrupt persisted IDs are retained instead of replacing stored data', () async {
    var raw = '[invalid';
    final store = SavedReportNotificationRetryStore(read: (_) async => raw,
      write: (_, value) async { raw = value; });
    await expectLater(store.remember(original), throwsFormatException);
    expect(raw, '[invalid');
  });
  test('persist precedes lookup and RPC; crash preserves fixed scope on restart', () async {
    final stored = <SavedReportNotificationRetry>[];
    final calls = <String>[];
    Future<bool> attempt(SavedReportNotificationRetry retry, {bool crash = false, bool sent = false}) =>
      retryPersistedSavedReportNotification(retry,
        remember: (value) async { if (stored.isEmpty) stored.add(value); calls.add('persist'); },
        verifySaved: (value) async { expect(value.companyId, 'company-a'); calls.add('lookup'); },
        publish: (id) async { calls.add(id); if (crash) throw StateError('connection lost'); return sent; },
        confirmed: (value) async { stored.remove(value); calls.add('confirmed'); });
    await expectLater(attempt(original, crash: true), throwsStateError);
    expect(calls, ['persist', 'lookup', 'saved-id']);
    final restored = stored.single; // New page/session uses the persisted identity.
    expect(restored.userId, 'user-a');
    expect(await attempt(restored), isFalse); // OFF / dedup zero must retain.
    expect(stored.single.reportId, 'saved-id');
    expect(await attempt(restored, sent: true), isTrue);
    expect(stored, isEmpty);
  });
  test('lookup failure or changed author cannot invoke RPC or remove ID', () async {
    var called = false;
    await expectLater(retryPersistedSavedReportNotification(original,
      remember: (_) async {},
      verifySaved: (_) async => throw StateError('lookup unavailable'),
      publish: (_) async { called = true; return true; },
      confirmed: (_) async { called = true; }), throwsStateError);
    expect(called, isFalse);
  });
  test('persistence failure prevents notification and removal', () async {
    var called = false;
    await expectLater(retryPersistedSavedReportNotification(original,
      remember: (_) async => throw StateError('disk failed'),
      verifySaved: (_) async { called = true; },
      publish: (_) async { called = true; return true; },
      confirmed: (_) async { called = true; }), throwsStateError);
    expect(called, isFalse);
  });
}
