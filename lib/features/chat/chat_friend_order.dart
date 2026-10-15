/// Registration order, with existing direct-chat friends stably promoted.
List<Map<String, dynamic>> orderChatFriends(
  List<Map<String, dynamic>> friends,
  Iterable<Map<String, dynamic>> groups, {
  Set<String> pinnedUserIds = const {},
}) {
  final directUsers = {
    for (final group in groups)
      if (group['group_type'] == 'direct' &&
          (group['direct_other_user_id']?.toString() ?? '').isNotEmpty)
        group['direct_other_user_id'].toString(),
  };
  final indexed = friends.indexed.toList();
  // Without complete dates, preserve the server order rather than inventing
  // a registration order for undated rows.
  if (friends.every((row) => DateTime.tryParse(row['created_at']?.toString() ?? '') != null)) {
    indexed.sort((a, b) {
      final at = DateTime.parse(a.$2['created_at'].toString());
      final bt = DateTime.parse(b.$2['created_at'].toString());
      final result = at.compareTo(bt);
      return result != 0 ? result : a.$1.compareTo(b.$1);
    });
  }
  final ordered = indexed.map((item) => item.$2).toList();
  return [
    for (final friend in ordered)
      if (pinnedUserIds.contains(friend['user_id']?.toString())) friend,
    for (final friend in ordered)
      if (!pinnedUserIds.contains(friend['user_id']?.toString()) &&
          directUsers.contains(friend['user_id']?.toString()))
        friend,
    for (final friend in ordered)
      if (!pinnedUserIds.contains(friend['user_id']?.toString()) &&
          !directUsers.contains(friend['user_id']?.toString()))
        friend,
  ];
}
