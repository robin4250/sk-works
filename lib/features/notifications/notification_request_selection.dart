import 'notification_target_policy.dart';

/// Narrows already-authorized rows for a notification without granting access.
/// Null is the ordinary inbox; every non-null target must be an exact UUID.
List<T> selectNotificationRequestRows<T>(
  Iterable<T> rows, {
  required String? requestId,
  required String Function(T) id,
  bool Function(T)? includeInInbox,
}) {
  if (requestId == null) {
    return List<T>.unmodifiable(
      includeInInbox == null ? rows : rows.where(includeInInbox),
    );
  }
  if (!notificationTargetIsValid('site_information_request', requestId)) {
    return List<T>.unmodifiable(const []);
  }
  return List<T>.unmodifiable(rows.where((row) => id(row) == requestId));
}
