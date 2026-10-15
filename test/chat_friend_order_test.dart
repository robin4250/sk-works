import 'package:flutter_test/flutter_test.dart';

import '../lib/features/chat/chat_friend_order.dart';

void main() {
  test('only direct peers are promoted and both partitions keep registration order', () {
    final rows = [
      {'user_id': 'late', 'created_at': '2026-10-03'},
      {'user_id': 'first', 'created_at': '2026-10-01'},
      {'user_id': 'middle', 'created_at': '2026-10-02'},
      {'user_id': 'last', 'created_at': '2026-10-04'},
    ];
    final result = orderChatFriends(rows, [
      {'group_type': 'direct', 'direct_other_user_id': 'late'},
      {'group_type': 'direct', 'direct_other_user_id': 'middle'},
      {'group_type': 'company', 'direct_other_user_id': 'first'},
    ]);
    expect(result.map((row) => row['user_id']), [
      'middle',
      'late',
      'first',
      'last',
    ]);
    expect(rows.first['user_id'], 'late');
  });
  test('missing or tied dates preserve server order', () {
    final rows = [
      {'user_id': 'a'},
      {'user_id': 'b'},
    ];
    expect(orderChatFriends(rows, []).map((row) => row['user_id']), ['a', 'b']);
  });
}
