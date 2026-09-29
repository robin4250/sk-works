class SiteChatLifecycle {
  const SiteChatLifecycle._();

  /// Every registered site owns one site-chat group.
  static bool shouldCreateChatOnSiteRegistration() => true;

  /// A worker joins automatically when attendance is first recorded for the site.
  static bool shouldAutoJoinOnAttendance({
    required bool attendanceRecorded,
    required bool alreadyMember,
  }) =>
      attendanceRecorded && !alreadyMember;

  /// Company managers may enter for operational oversight without attendance.
  static bool canManagerEnterWithoutAttendance(String role) =>
      role == 'owner' || role == 'admin' || role == 'sub_admin';

  /// Site closure archives the chat; history is preserved instead of deleted.
  static bool shouldArchiveOnSiteClosure() => true;

  /// Financial/admin-only site fields must never be published to site chat.
  static const publicSiteCardFields = <String>{
    'name',
    'address',
    'nearest_station',
    'starts_on',
    'ends_on',
  };
}
