import 'package:flutter/material.dart';

import '../auth/employee_onboarding_approvals_page.dart';
import '../attendance/attendance_correction_approvals_page.dart';
import '../daily_reports/daily_report_approvals_page.dart';
import '../notifications/notification_bell.dart';

class ApprovalsHubPage extends StatelessWidget {
  const ApprovalsHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '承認待ち',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: const [SkoNotificationBell()],
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
                title: const Text(
                  '日報の承認待ち',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: const Text('日報修正申請の承認・却下'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const DailyReportApprovalsPage(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.edit_calendar_outlined),
                ),
                title: const Text(
                  '勤務修正の承認待ち',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: const Text('1日・複数日の勤務修正申請を確認して承認'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AttendanceCorrectionApprovalsPage(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.verified_user_outlined),
                ),
                title: const Text(
                  '従業員の本登録承認',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: const Text('本登録待ちの従業員を確認して承認'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const EmployeeOnboardingApprovalsPage(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
