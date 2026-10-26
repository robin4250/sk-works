import '../auth/secondary_protected_page.dart';
import 'attendance_management_page.dart';
import 'attendance_management_repository.dart';
import 'attendance_worker_list_page.dart';

SecondaryProtectedPage attendanceWorkerListDestination({Future<void> Function()? onOpenManagement}) =>
    SecondaryProtectedPage(title: '出勤表一覧',
      child: AttendanceWorkerListPage(onOpenManagement: onOpenManagement));

SecondaryProtectedPage attendanceManagementDestination({
  AttendanceManagementRepository? repository, String? initialWorkerId,
  DateTime? initialDate, bool restrictedRecovery = false,
}) {
  final managedRepository = repository ?? AttendanceManagementRepository.maybeCreate();
  return SecondaryProtectedPage(title: '勤怠管理',
    entryAccess: managedRepository == null ? null : () => managedRepository.entryAccess,
    child: AttendanceManagementPage(
      repository: managedRepository, initialWorkerId: initialWorkerId,
      initialDate: initialDate, restrictedRecovery: restrictedRecovery));
}
