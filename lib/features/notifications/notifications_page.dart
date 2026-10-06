import 'package:flutter/material.dart';

import 'app_notification_repository.dart';
import '../auth/secondary_protected_page.dart';
import '../invoices/invoice_cloud_page.dart';
import '../chat/chat_cloud_page.dart';
import '../payroll/individual_payroll_settings_page.dart';
import '../payroll/payment_certificates_page.dart';
import '../settings/settings_page.dart';
import '../sites/admin_site_financial_page.dart';
import '../attendance/paid_leave_approvals_page.dart';
import '../attendance/attendance_correction_approvals_page.dart';
import '../sites/site_map_page.dart';
import '../sites/site_share_approval_page.dart';
import '../sites/site_information_approvals_page.dart';
import '../operations/vehicle_route_page.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final _repository = AppNotificationRepository.maybeCreate();

  List<AppNotificationRecord> _items = const [];
  bool _loading = true;
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
    final repository = _repository;
    if (repository != null && !item.read) {
      await repository.markRead(item.id);
    }
    if (!mounted) return;

    if (item.actionKey == 'chat_group_invite') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const ChatCloudPage(showGroupsInitially: true),
        ),
      );
      if (!mounted) return;
      await _load();
      return;
    }
    if (item.actionKey == 'site_map') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const GeneralSiteMapPage(),
        ),
      );
      if (!mounted) return;
      await _load();
      return;
    }
    if (item.actionKey == 'site_share_approval') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const SiteShareApprovalPage(),
        ),
      );
      if (!mounted) return;
      await _load();
      return;
    }
    if (item.actionKey == 'site_information_request' ||
        item.actionKey == 'site_information_request_result') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SiteInformationApprovalsPage(
            initialRequestId: item.actionId,
          ),
        ),
      );
      if (!mounted) return;
      await _load();
      return;
    }
    if (item.actionKey == 'vehicle_documents') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const VehicleRoutePage(),
        ),
      );
      if (!mounted) return;
      await _load();
      return;
    }
    if (item.actionKey == 'paid_leave_request') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const PaidLeaveApprovalsPage(),
        ),
      );
      if (!mounted) return;
      await _load();
      return;
    }
    if (item.actionKey == 'attendance_correction_request') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AttendanceCorrectionApprovalsPage(
            initialRequestId: item.actionId,
          ),
        ),
      );
      if (!mounted) return;
      await _load();
      return;
    }
    if (item.actionKey == 'payroll_settings') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const SecondaryProtectedPage(
            title: '個別給与設定',
            child: IndividualPayrollSettingsPage(),
          ),
        ),
      );
      if (!mounted) return;
      await _load();
      return;
    }
    if (item.actionKey == 'admin_sites') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const SecondaryProtectedPage(
            title: '管理者用現場データ',
            child: AdminSiteFinancialPage(),
          ),
        ),
      );
      if (!mounted) return;
      await _load();
      return;
    }
    if (item.actionKey == 'invoice_approval') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => InvoiceCloudPage(
            initialInvoiceId: item.actionId,
          ),
        ),
      );
      if (!mounted) return;
      await _load();
      return;
    }
    if (item.actionKey == 'payment_certificate_settings') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const SecondaryProtectedPage(
            title: '支払証明書設定',
            child: PartnerPaymentSettingsPage(),
          ),
        ),
      );
      if (!mounted) return;
      await _load();
      return;
    }
    if (item.actionKey == 'settings') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const SettingsPage(),
        ),
      );
      if (!mounted) return;
      await _load();
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          item.actionKey == null
              ? 'お知らせを確認しました'
              : '関連画面への案内を準備しています',
        ),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'お知らせ',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          if (_items.any((item) => !item.read))
            TextButton(
              onPressed: _markAll,
              child: const Text('すべて既読'),
            ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.notifications_off_outlined, size: 46),
                          const SizedBox(height: 12),
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _load,
                            icon: const Icon(Icons.refresh),
                            label: const Text('再読み込み'),
                          ),
                        ],
                      ),
                    ),
                  )
                : _items.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.notifications_none, size: 52),
                            SizedBox(height: 12),
                            Text(
                              '新しいお知らせはありません',
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
                                onTap: () => _open(item),
                              ),
                            );
                          },
                        ),
                      ),
      ),
    );
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
