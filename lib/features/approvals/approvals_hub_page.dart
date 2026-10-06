import 'package:flutter/material.dart';

import '../../international/language_controller.dart';
import '../auth/employee_onboarding_approvals_page.dart';
import '../auth/employee_onboarding_repository.dart';
import '../attendance/attendance_correction_approvals_page.dart';
import '../attendance/attendance_correction_approval_repository.dart';
import '../attendance/paid_leave_approvals_page.dart';
import '../attendance/paid_leave_repository.dart';
import '../daily_reports/daily_report_approvals_page.dart';
import '../daily_reports/daily_report_repository.dart';
import '../notifications/notification_bell.dart';
import '../people/people_cloud_repository.dart';
import '../people/worker_personnel_change_approvals_page.dart';
import '../sites/site_cloud_repository.dart';
import '../sites/site_information_approvals_page.dart';

class ApprovalsHubPage extends StatefulWidget {
  const ApprovalsHubPage({super.key});

  @override
  State<ApprovalsHubPage> createState() => _ApprovalsHubPageState();
}

class _ApprovalsHubPageState extends State<ApprovalsHubPage> {
  final _dailyRepository = DailyReportRepository.maybeCreate();
  final _attendanceRepository =
      AttendanceCorrectionApprovalRepository.maybeCreate();
  final _paidLeaveRepository = PaidLeaveRepository.maybeCreate();
  final _onboardingRepository = EmployeeOnboardingRepository.maybeCreate();
  final _siteRepository = SiteCloudRepository.maybeCreate();
  final _peopleRepository = PeopleCloudRepository.maybeCreate();

  int _dailyCount = 0;
  int _attendanceCount = 0;
  int _paidLeaveCount = 0;
  int _onboardingCount = 0;
  int _siteInformationCount = 0;
  int _personnelChangeCount = 0;
  bool _loadingCounts = true;

  @override
  void initState() {
    super.initState();
    _loadCounts();
  }

  Future<void> _loadCounts() async {
    Future<int> safe(Future<int> Function() load) async {
      try {
        return await load();
      } catch (_) {
        return 0;
      }
    }

    final values = await Future.wait<int>([
      safe(() async => (await _dailyRepository?.loadPendingApprovals())?.length ?? 0),
      safe(() async => (await _attendanceRepository?.loadPending())?.length ?? 0),
      safe(() async => (await _paidLeaveRepository?.loadPendingApprovals())?.length ?? 0),
      safe(() async {
        final repository = _onboardingRepository;
        if (repository == null || !await repository.canReview()) return 0;
        return (await repository.loadPendingApprovals()).length;
      }),
      safe(() async {
        final repository = _siteRepository;
        if (repository == null) return 0;
        final items = await repository.loadInformationRequests();
        return items.where((item) =>
          item['status']?.toString() == 'pending' && item['can_review'] == true
        ).length;
      }),
      safe(() async {
        final repository = _peopleRepository;
        if (repository == null) return 0;
        return (await repository.loadPendingPersonnelChanges()).length;
      }),
    ]);
    if (!mounted) return;
    setState(() {
      _dailyCount = values[0];
      _attendanceCount = values[1];
      _paidLeaveCount = values[2];
      _onboardingCount = values[3];
      _siteInformationCount = values[4];
      _personnelChangeCount = values[5];
      _loadingCounts = false;
    });
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => page),
    );
    if (!mounted) return;
    await _loadCounts();
  }

  Widget _trailing(int count) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_loadingCounts)
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else if (count > 0)
          Container(
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
            ),
            child: Text(
              count > 99 ? '99+' : '$count',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ),
        const SizedBox(width: 6),
        const Icon(Icons.chevron_right),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          SkoLanguageController.tr('承認待ち'),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: SkoLanguageController.tr('件数を更新'),
            onPressed: _loadingCounts ? null : _loadCounts,
            icon: const Icon(Icons.refresh),
          ),
          const SkoNotificationBell(),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Card(
              child: ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.edit_note_outlined),
                ),
                title: Text(
                  SkoLanguageController.tr('日報の承認待ち'),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text(SkoLanguageController.tr('日報修正申請の承認・却下')),
                trailing: _trailing(_dailyCount),
                onTap: () => _open(const DailyReportApprovalsPage()),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.edit_calendar_outlined),
                ),
                title: Text(
                  SkoLanguageController.tr('勤務修正の承認待ち'),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text(SkoLanguageController.tr('勤務修正・過去まとめて出勤の申請を確認して承認')),
                trailing: _trailing(_attendanceCount),
                onTap: () => _open(const AttendanceCorrectionApprovalsPage()),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.event_available_outlined),
                ),
                title: Text(
                  SkoLanguageController.tr('有給申請の承認待ち'),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text(SkoLanguageController.tr('有給申請を確認して承認・却下')),
                trailing: _trailing(_paidLeaveCount),
                onTap: () => _open(const PaidLeaveApprovalsPage()),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.apartment_outlined),
                ),
                title: Text(
                  SkoLanguageController.tr('現場データの承認待ち'),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text(
                  SkoLanguageController.tr('現場情報の変更・終了申請を確認して承認'),
                ),
                trailing: _trailing(_siteInformationCount),
                onTap: () => _open(const SiteInformationApprovalsPage()),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.manage_accounts_outlined),
                ),
                title: Text(
                  SkoLanguageController.tr('社員個人情報の変更承認'),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text(
                  SkoLanguageController.tr('社員個人情報の変更申請を確認して承認・拒否'),
                ),
                trailing: _trailing(_personnelChangeCount),
                onTap: () =>
                    _open(const WorkerPersonnelChangeApprovalsPage()),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.verified_user_outlined),
                ),
                title: Text(
                  SkoLanguageController.tr('従業員の本登録承認'),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text(SkoLanguageController.tr('本登録待ちの従業員を確認して承認')),
                trailing: _trailing(_onboardingCount),
                onTap: () => _open(const EmployeeOnboardingApprovalsPage()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
