import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/notifications/notification_request_selection.dart';

void main() {
  const target = '11111111-1111-4111-8111-111111111111';
  const other = '22222222-2222-4222-8222-222222222222';
  final pending = {'id': other, 'status': 'pending'};
  final completed = {'id': target, 'status': 'approved'};
  final rows = [pending, completed];
  test('ordinary inbox retains only its existing status predicate without mutation', () {
    final visible = selectNotificationRequestRows(
      rows,
      requestId: null,
      id: (row) => row['id']!,
      includeInInbox: (row) => row['status'] == 'pending',
    );
    expect(visible, [same(pending)]);
    expect(rows, [same(pending), same(completed)]);
    expect(() => visible.clear(), throwsUnsupportedError);
  });
  test('exact notification target includes completed record without other pending requests', () {
    final visible = selectNotificationRequestRows(
      rows,
      requestId: target,
      id: (row) => row['id']!,
      includeInInbox: (row) => row['status'] == 'pending',
    );
    expect(visible, [same(completed)]);
    expect(() => visible.clear(), throwsUnsupportedError);
  });
}
