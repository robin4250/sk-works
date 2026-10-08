import '../../international/language_controller.dart';
import 'package:flutter/material.dart';

import 'app_notification_repository.dart';
import 'notification_business_status.dart';
import '../auth/secondary_protected_page.dart';
import '../invoices/invoice_cloud_page.dart';
import '../chat/chat_cloud_page.dart';
import '../payroll/individual_payroll_settings_page.dart';
import '../payroll/payroll_review_page.dart';
import '../payroll/payroll_review_repository.dart';
import '../payroll/payment_certificates_page.dart';
import '../settings/settings_page.dart';
import '../sites/admin_site_financial_page.dart';
import '../attendance/paid_leave_approvals_page.dart';
import '../daily_reports/daily_report_approvals_page.dart';
import '../attendance/attendance_correction_approvals_page.dart';
import '../sites/site_map_page.dart';
import '../sites/site_share_approval_page.dart';
import '../sites/site_information_approvals_page.dart';
import '../operations/vehicle_route_page.dart';
import '../people/people_cloud_page.dart';
import '../people/worker_personnel_change_approvals_page.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final _repository = AppNotificationRepository.maybeCreate();

  List<AppNotificationRecord> _items = const [];
  bool _loading = true;
  bool _opening = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repository = _repository;
    if (repository == null) {
      setState(() {
        _loading = false;
        _error = '通知センターを利用できません。';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final items = await repository.load();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _markAll() async {
    final repository = _repository;
    if (repository == null) return;
    await repository.markAllRead();
    await _load();
  }

  Future<void> _open(AppNotificationRecord item) async {
    if (_opening) return;
    _opening = true;
    try {
    // Resolve before changing read state. Unsupported actions remain unread.
    Widget? destination;
    try {
      DateTime? payrollMonth;
      if (item.actionKey == 'payroll_review') {
        final review = PayrollReviewRepository.maybeCreate();
        if (review == null) throw StateError('Payroll review is unavailable');
        payrollMonth = await review.notificationMonth(item.actionId ?? '');
      }
      destination = notificationDestination(item, payrollMonth: payrollMonth);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(SkoLanguageController.tr('対象の給与明細を開けません。閲覧権限と通知の対象を確認してください。')),
      ));
      return; // Failed resolution leaves the notification unread.
    }
    if (!mounted) return;
    if (destination == null && item.actionKey != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(SkoLanguageController.tr('関連画面への案内を準備しています')),
      ));
      return;
    }
    try {
      final repository = _repository;
      if (repository != null && !item.read) {
        await repository.markRead(item.id);
      }
      if (!mounted) return;
      final targetPage = destination;
      if (targetPage != null) {
        await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => targetPage,
        ));
        if (!mounted) return;
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(SkoLanguageController.tr('お知らせを確認しました')),
        ));
      }
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(SkoLanguageController.trParams(
          '通知を開けませんでした: {error}', {'error': error},
        )),
      ));
    }
    } finally {
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          SkoLanguageController.tr('お知らせ'),
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          if (_items.any((item) => !item.read))
            TextButton(
              onPressed: _markAll,
              child: Text(SkoLanguageController.tr('すべて既読')),
            ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.notifications_off_outlined, size: 46),
                          const SizedBox(height: 12),
                          Text(SkoLanguageController.tr(_error!), textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _load,
                            icon: const Icon(Icons.refresh),
                            label: Text(SkoLanguageController.tr('再読み込み')),
                          ),
                        ],
                      ),
                    ),
                  )
                : _items.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.notifications_none, size: 52),
                            SizedBox(height: 12),
                            Text(
                              SkoLanguageController.tr('新しいお知らせはありません'),
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: _items.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final item = _items[index];
                            return Card(
                              child: ListTile(
                                leading: CircleAvatar(
                                  child: Icon(_icon(item.kind)),
                                ),
                                title: Text(
                                  item.title,
                                  style: TextStyle(
                                    fontWeight:
                                        item.read ? FontWeight.w600 : FontWeight.w900,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (item.body.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(item.body),
                                    ],
                                    if (item.hasBusinessTarget) ...[
                                      const SizedBox(height: 4),
                                      Text(_businessDescription(item)),
                                    ],
                                    const SizedBox(height: 4),
                                    Text(
                                      _formatDate(item.createdAt),
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                                trailing: item.read
                                    ? const Icon(Icons.chevron_right)
                                    : const Badge(
                                        child: Icon(Icons.chevron_right),
                                      ),
                                onTap: _opening ? null : () => _open(item),
                              ),
                            );
                          },
                        ),
                      ),
      ),
    );
  }

  String _businessDescription(AppNotificationRecord item) {
    final status = item.businessStatus;
    final label = switch (status.state) {
      NotificationBusinessState.pending => '未確認',
      NotificationBusinessState.completed => '確認済み',
      NotificationBusinessState.rejected => '却下済み',
      NotificationBusinessState.cancelled => '取消済み',
      NotificationBusinessState.unknown => '状態を確認できません',
    };
    final date = status.targetDate;
    final targetDate = date == null ? null
        : item.actionKey == 'payroll_review' || item.actionKey == 'invoice_approval'
            ? '${date.year}/${date.month.toString().padLeft(2, '0')}'
            : '${date.year}/${date.month}/${date.day}';
    return [
      if (status.targetName?.isNotEmpty == true) status.targetName!,
      if (targetDate != null) targetDate,
      SkoLanguageController.tr(label),
    ].join(' / ');
  }

  IconData _icon(String kind) => switch (kind) {
        'approval' => Icons.approval_outlined,
        'warning' => Icons.warning_amber_outlined,
        'attendance' => Icons.schedule_outlined,
        'document' => Icons.description_outlined,
        'chat' || 'chat_group_invite' => Icons.chat_bubble_outline,
        _ => Icons.notifications_outlined,
      };

  String _formatDate(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${value.year}/${two(value.month)}/${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}';
  }
}

/// Known notification routes reuse the same protected pages as the home menu.
/// Repositories in each destination retain their existing access checks and RLS.
Widget? notificationDestination(AppNotificationRecord item, {DateTime? payrollMonth}) => switch (item.actionKey) {
  'chat_group_invite' => const ChatCloudPage(showGroupsInitially: true),
  'site_map' => const GeneralSiteMapPage(),
  'site_share_approval' => SiteShareApprovalPage(initialRequestId: item.actionId),
  'site_information_request' || 'site_information_request_result' =>
    SiteInformationApprovalsPage(initialRequestId: item.actionId),
  'vehicle_documents' => const VehicleRoutePage(),
  'daily_report_edit_request' =>
    DailyReportApprovalsPage(initialRequestId: item.actionId),
  'paid_leave_request' => PaidLeaveApprovalsPage(initialRequestId: item.actionId),
  'attendance_correction_request' =>
    AttendanceCorrectionApprovalsPage(initialRequestId: item.actionId),
  'worker_personnel_change' =>
    WorkerPersonnelChangeApprovalsPage(initialRequestId: item.actionId),
  'worker_personnel_change_completed' => const PeopleCloudPage(),
  'payroll_settings' => SecondaryProtectedPage(
    title: SkoLanguageController.tr('個別給与設定'),
    child: const IndividualPayrollSettingsPage(),
  ),
  'payroll_review' => SecondaryProtectedPage(
    title: SkoLanguageController.tr('給料一覧'),
    child: PayrollReviewPage(initialMonth: payrollMonth),
  ),
  'admin_sites' => SecondaryProtectedPage(
    title: SkoLanguageController.tr('管理者用現場データ'),
    child: const AdminSiteFinancialPage(),
  ),
  'invoice_approval' => InvoiceCloudPage(initialInvoiceId: item.actionId),
  'payment_certificate_settings' => SecondaryProtectedPage(
    title: SkoLanguageController.tr('支払証明書設定'),
    child: const PartnerPaymentSettingsPage(),
  ),
  'settings' => const SettingsPage(),
  _ => null,
};
