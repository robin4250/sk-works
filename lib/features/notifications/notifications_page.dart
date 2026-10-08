import '../../international/language_controller.dart';
import 'package:flutter/material.dart';

import 'app_notification_repository.dart';
import 'source_notification_target.dart';
import 'source_notification_target_page.dart';
import 'attention_center_repository.dart';
import 'attention_center_item.dart';
import '../people/own_document_registration_page.dart';
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
  final _repository = AttentionCenterRepository.maybeCreate();
  final _notifications = AppNotificationRepository.maybeCreate();
  AttentionCenterData? _data;
  bool _loading = true;
  bool _opening = false;
  bool _pendingOnly = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repository = _repository;
    if (repository == null) {
      if (mounted) {
        setState(() { _loading = false; _error = '通知センターを利用できません。'; });
      }
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final data = await repository.load();
      if (!mounted) {
        return;
      }
      setState(() { _data = data; _loading = false; });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() { _loading = false; _error = error.toString(); });
    }
  }

  Future<void> _markAll() async {
    try {
      await _notifications?.markAllRead();
      await _load();
    } catch (error) {
      _showError(error);
    }
  }

  void _showError(Object error) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
      SkoLanguageController.trParams('通知を開けませんでした: {error}', {'error': error}),
    )));
  }

  Future<void> _open(AttentionCenterItem item) async {
    if (_opening) {
      return;
    }
    setState(() => _opening = true);
    try {
      final data = _data;
      final ids = data?.notificationIdsByItemKey[item.deduplicationKey] ?? const <String>[];
      final record = ids.isNotEmpty ? data?.notificationsById[ids.first] : null;
      final target = record ?? AppNotificationRecord(
        id: '', kind: item.source, title: item.title, body: item.body,
        createdAt: item.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
        read: true, actionKey: item.actionKey, actionId: item.actionId,
      );
      DateTime? payrollMonth;
      if (target.actionKey == 'payroll_review') {
        final review = PayrollReviewRepository.maybeCreate();
        if (review == null) {
          throw StateError('Payroll review is unavailable');
        }
        payrollMonth = await review.notificationMonth(target.actionId ?? '');
      }
      Widget? destination;
      if (SourceNotificationTarget.supports(target.actionKey)) {
        final repository = _notifications;
        if (repository == null) {
          throw StateError('Notifications unavailable');
        }
        final savedTarget = await repository.sourceTarget(target);
        destination = SourceNotificationTargetPage(target: savedTarget);
      } else {
        destination = notificationDestination(target, payrollMonth: payrollMonth);
      }
      if (!mounted) {
        return;
      }
      if (destination == null && target.actionKey != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
          SkoLanguageController.tr('関連画面への案内を準備しています'),
        )));
        return;
      }
      // System tasks have no notification id and never write a synthetic read state.
      for (final id in ids) {
        if (data?.notificationsById[id]?.read == false) {
          await _notifications?.markRead(id);
        }
      }
      if (!mounted) {
        return;
      }
      final page = destination;
      if (page != null) {
        await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
          SkoLanguageController.tr('お知らせを確認しました'),
        )));
      }
      if (mounted) {
        await _load();
      }
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) {
        setState(() => _opening = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    final data = _data;
    final items = data?.snapshot.items.where((item) => !_pendingOnly || item.needsAction).toList()
        ?? const <AttentionCenterItem>[];
    return Scaffold(
      appBar: AppBar(
        title: Text(SkoLanguageController.tr('お知らせ'), style: const TextStyle(fontWeight: FontWeight.w900)),
        actions: [if (data?.notificationsById.values.any((item) => !item.read) == true)
          TextButton(onPressed: _opening ? null : _markAll,
            child: Text(SkoLanguageController.tr('すべて既読')))],
      ),
      body: SafeArea(child: Column(children: [
        Padding(padding: const EdgeInsets.all(12), child: SegmentedButton<bool>(
          segments: [
            ButtonSegment(value: false, label: Text(SkoLanguageController.tr('すべて'))),
            ButtonSegment(value: true, label: Text(SkoLanguageController.tr('要対応'))),
          ], selected: {_pendingOnly},
          onSelectionChanged: (values) => setState(() => _pendingOnly = values.single),
        )),
        if (data?.unavailableSources.isNotEmpty == true)
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(SkoLanguageController.tr('一部のお知らせを取得できません。再読み込みしてください。'))),
        if (_error != null)
          Padding(padding: const EdgeInsets.all(16), child: Text(SkoLanguageController.tr(_error!))),
        Expanded(child: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(onRefresh: _load, child: ListView(
              physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(12),
              children: [
                if (items.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Center(
                  child: Text(SkoLanguageController.tr(_pendingOnly
                    ? '未対応の項目はありません' : '新しいお知らせはありません')))),
                for (final item in items) Card(child: ListTile(
                  leading: CircleAvatar(child: Icon(item.needsAction
                    ? Icons.notifications_active_outlined : Icons.notifications_outlined)),
                  title: Text(item.title, style: TextStyle(fontWeight:
                    item.needsAction || !item.read ? FontWeight.w900 : FontWeight.w600)),
                  subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (item.body.isNotEmpty) Text(item.body),
                    if (item.state != AttentionCenterState.information) Text(_businessDescription(item)),
                    if (item.createdAt != null) Text(_formatDate(item.createdAt!),
                      style: Theme.of(context).textTheme.bodySmall),
                  ]),
                  trailing: item.source == 'notification' && !item.read
                    ? const Badge(child: Icon(Icons.chevron_right)) : const Icon(Icons.chevron_right),
                  onTap: _opening ? null : () => _open(item),
                )),
              ],
            ))),
      ])),
    );
  }

  String _businessDescription(AttentionCenterItem item) {
    final label = switch (item.state) {
      AttentionCenterState.pending => '未確認',
      AttentionCenterState.completed => '確認済み',
      AttentionCenterState.rejected => '却下済み',
      AttentionCenterState.cancelled => '取消済み',
      AttentionCenterState.unknown => '状態を確認できません',
      AttentionCenterState.information => '',
    };
    final date = item.targetDate;
    final targetDate = date == null ? null
      : item.actionKey == 'payroll_review' || item.actionKey == 'invoice_approval'
        ? '${date.year}/${date.month.toString().padLeft(2, '0')}'
        : '${date.year}/${date.month}/${date.day}';
    return [if (item.targetName?.isNotEmpty == true) item.targetName!,
      if (targetDate != null) targetDate, SkoLanguageController.tr(label)].join(' / ');
  }

  String _formatDate(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${value.year}/${two(value.month)}/${two(value.day)} ${two(value.hour)}:${two(value.minute)}';
  }
}

/// Known notification routes reuse the same protected pages as the home menu.
/// Repositories in each destination retain their existing access checks and RLS.
Widget? notificationDestination(AppNotificationRecord item, {DateTime? payrollMonth}) => switch (item.actionKey) {
  'document_register' => const OwnDocumentRegistrationPage(),
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
