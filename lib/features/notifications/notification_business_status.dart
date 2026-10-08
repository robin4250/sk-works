/// Business completion is independent of a notification's read_at timestamp.
enum NotificationBusinessState { pending, completed, rejected, cancelled, unknown }

class NotificationBusinessStatus {
  const NotificationBusinessStatus({
    this.state = NotificationBusinessState.unknown,
    this.targetName,
    this.targetDate,
  });

  final NotificationBusinessState state;
  final String? targetName;
  final DateTime? targetDate;

  static NotificationBusinessStatus fromRows(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) {
      return const NotificationBusinessStatus();
    }
    final states = rows.map((row) => stateFromValue(row['status'])).toList();
    final state = states.contains(NotificationBusinessState.unknown)
        ? NotificationBusinessState.unknown
        : states.contains(NotificationBusinessState.pending)
            ? NotificationBusinessState.pending
            : states.contains(NotificationBusinessState.rejected)
                ? NotificationBusinessState.rejected
                : states.contains(NotificationBusinessState.cancelled)
                    ? NotificationBusinessState.cancelled
                    : NotificationBusinessState.completed;
    final first = rows.first;
    final worker = first['workers'];
    return NotificationBusinessStatus(
      state: state,
      targetName: worker is Map ? worker['name']?.toString() : null,
      targetDate: DateTime.tryParse(
        (first['period_start'] ?? first['billing_period_start'] ?? first['leave_date'] ?? first['report_date'])
                ?.toString() ?? '',
      ),
    );
  }

  static NotificationBusinessState stateFromValue(Object? value) => switch (value) {
        'pending' || 'submitted' => NotificationBusinessState.pending,
        'approved' || 'used' => NotificationBusinessState.completed,
        'rejected' => NotificationBusinessState.rejected,
        'cancelled' => NotificationBusinessState.cancelled,
        _ => NotificationBusinessState.unknown,
      };
}

/// A reviewer completing their own task must not remain pending merely because
/// another reviewer has not yet completed the same month.
NotificationBusinessState payrollNotificationState({
  required String expectedPeriod,
  required String? currentUserId,
  required Object? value,
}) {
  if (value is! Map || value['period_start']?.toString() != expectedPeriod ||
      currentUserId == null || currentUserId.isEmpty) {
    return NotificationBusinessState.unknown;
  }
  final reviewers = value['reviewers'];
  if (reviewers is! List) {
    return NotificationBusinessState.unknown;
  }
  final assigned = reviewers.any((reviewer) =>
      reviewer is Map && reviewer['user_id'] == currentUserId);
  if (assigned) {
    return switch (value['reviewer_confirmed']) {
      true => NotificationBusinessState.completed,
      false => NotificationBusinessState.pending,
      _ => NotificationBusinessState.unknown,
    };
  }
  return value['confirmed'] == true
      ? NotificationBusinessState.completed
      : NotificationBusinessState.unknown;
}
