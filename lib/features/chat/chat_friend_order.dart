/// Registration order, with existing direct-chat friends stably promoted.
List<Map<String, dynamic>> orderChatFriends(
  List<Map<String, dynamic>> friends,
  Iterable<Map<String, dynamic>> groups,
) {
  final directUsers = {
    for (final group in groups)
      if (group['group_type'] == 'direct' &&
          (group['direct_other_user_id']?.toString() ?? '').isNotEmpty)
        group['direct_other_user_id'].toString(),
  };
  final indexed = friends.indexed.toList();
  indexed.sort((a, b) {
    final at = DateTime.tryParse(a.$2['created_at']?.toString() ?? '');
    final bt = DateTime.tryParse(b.$2['created_at']?.toString() ?? '');
    if (at != null && bt != null) {
      final result = at.compareTo(bt);
      if (result != 0) return result;
    } else if (at != null || bt != null) {
      return at != null ? -1 : 1;
    }
    return a.$1.compareTo(b.$1);
  });
  final ordered = indexed.map((item) => item.$2).toList();
  return [
    for (final friend in ordered)
      if (directUsers.contains(friend['user_id']?.toString())) friend,
    for (final friend in ordered)
      if (!directUsers.contains(friend['user_id']?.toString())) friend,
  ];
}
