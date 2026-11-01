import '../qualifications/qualification_photo_submission_review_page.dart';
import 'dart:async';
import 'notification_open_session.dart';
import 'checkout_report_notification_repository.dart';
import 'checkout_report_notification_page.dart';
import 'notification_explanation_page.dart';
import 'notification_target_policy.dart';
import '../../international/language_controller.dart';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../sites/site_order_site_actions.dart';
import '../sites/site_order_workflow_repository.dart';

import '../expenses/expense_notification_page.dart';
import 'app_notification_repository.dart';
import 'source_notification_target.dart';
import 'source_notification_target_page.dart';
import 'attention_center_repository.dart';
import 'attention_center_item.dart';
import '../settings/company_module_settings_repository.dart';
import '../../data/supabase_backend.dart';
import '../companies/company_profile_review_page.dart';
import '../companies/company_link_page.dart';
import '../companies/trade_company_repository.dart';
import '../people/own_document_registration_page.dart';
import '../auth/secondary_protected_page.dart';
import '../invoices/invoice_notification_page.dart';
import '../chat/chat_cloud_page.dart';
import '../payroll/individual_payroll_settings_page.dart';
import '../payroll/resident_tax_annual_page.dart';
import '../payroll/resident_tax_reminder_panel.dart';
import '../payroll/resident_tax_reminder_repository.dart';
import '../payroll/payroll_review_page.dart';
import '../attendance/attendance_notification_page.dart';
import '../payroll/payroll_review_repository.dart';
import '../payroll/payment_certificates_page.dart';
import '../payroll/site_contract_notification_page.dart';
import '../settings/settings_page.dart';
import '../settings/master_protected_page.dart';
import '../security/security_incident_page.dart';
import '../security/security_actor_boundary.dart';
import '../sites/admin_site_financial_page.dart';
import '../attendance/paid_leave_approvals_page.dart';
import '../daily_reports/daily_report_approvals_page.dart';
import '../daily_reports/daily_report_page.dart';
import '../attendance/attendance_correction_approvals_page.dart';
import '../sites/site_map_notification_page.dart';
import '../sites/site_share_approval_page.dart';
import '../sites/site_information_approvals_page.dart';
import '../operations/vehicle_route_page.dart';
import '../people/people_cloud_page.dart';
import '../route_billing/route_billing_quantity_approvals_page.dart';
import '../people/worker_personnel_change_approvals_page.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key, this.companyId, this.currentCompany,
    this.attentionRepository, this.notificationRepository, this.notificationClient,
    this.siteOrderApiFactory});
  @visibleForTesting final AttentionCenterRepository? attentionRepository;
  @visibleForTesting final AppNotificationRepository? notificationRepository;
  @visibleForTesting final SupabaseClient? notificationClient;
  @visibleForTesting final SiteOrderWorkflowApi? Function()? siteOrderApiFactory;
  final String? companyId;
  final String? Function()? currentCompany;
  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  late final _repository = widget.attentionRepository ?? AttentionCenterRepository.maybeCreate();
  late final _notifications = widget.notificationRepository ?? AppNotificationRepository.maybeCreate();
  AttentionCenterData? _data;
  SiteOrderWorkflowApi? _siteOrderApi;
  SiteOrderNotificationReadScope? _siteOrderRead;
  String? _siteOrderCompany;
  bool _siteOrderBoundaryRetired = false;
  NotificationOpenSession? _session;
  StreamSubscription<void>? _sessionChanges;
  int _loadRequest = 0;
  bool _loading = true;
  bool _opening = false;
  bool _pendingOnly = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final client = widget.notificationClient ??
        (SupabaseBackend.isInitialized ? SupabaseBackend.client : null);
    if (client != null) {
      _session = NotificationOpenSession(actor: () => client.auth.currentUser?.id,
        changes: client.auth.onAuthStateChange.map((event) => event.session?.user.id));
      _sessionChanges = _session!.invalidations.listen((_) {
        if (mounted) setState(() { _data = null; _loading = false; _error = '通知一覧を開き直してください。'; });
      });
    }
    _load();
  }

  @override
  void didUpdateWidget(covariant NotificationsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_siteOrderApi != null &&
        (widget.currentCompany?.call() ?? widget.companyId) != _siteOrderCompany) {
      _retireSiteOrderBoundary();
    }
    if (oldWidget.companyId != widget.companyId) {
      _retireSiteOrderBoundary();
      _data = null;
      _load();
    }
  }

  void _retireSiteOrderBoundary() {
    // Deny callbacks synchronously, then notify surviving routes outside the
    // framework's build/unmount lock. An unrelated root modal is never popped.
    _siteOrderBoundaryRetired = true;
    final api = _siteOrderApi, scope = _siteOrderRead;
    scheduleMicrotask(() {
      scope?.retire();
      if (api != null && !api.invalidated) api.retireUiScope();
    });
  }

  @override
  void dispose() {
    _retireSiteOrderBoundary();
    _sessionChanges?.cancel();
    _session?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_loadRequest;
    final repository = _repository;
    if (repository == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '通知センターを利用できません。';
        });
      }
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _session?.requireCurrent();
      final data = await repository.load(companyId: widget.companyId, currentCompany: widget.currentCompany);
      _session?.requireCurrent();
      if (!mounted || request != _loadRequest) {
        return;
      }
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || request != _loadRequest) {
        return;
      }
      setState(() {
        _loading = false;
        _error = '通知を取得できません。再読み込みしてください。';
      });
    }
  }

  Future<void> _markAll() async {
    try {
      _session?.requireCurrent();
      await _notifications?.markAllRead();
      _session?.requireCurrent();
      await _load();
    } catch (error) {
      _showError(error);
    }
  }

  void _showError(Object error) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          SkoLanguageController.tr('操作結果を確認できません。通知の内容を確認し、もう一度お試しください。'),
        ),
      ),
    );
  }

  Future<void> _open(AttentionCenterItem item) async {
    if (_opening) {
      return;
    }
    if (!mounted) return;
    final session = _session;
    if (session == null || !session.isCurrent) return;
    final snapshot = _data;
    final capturedLoad = _loadRequest;
    final ids = snapshot?.notificationIdsByItemKey[item.deduplicationKey] ?? const <String>[];
    final saved = ids.isEmpty ? null : snapshot?.notificationsById[ids.first];
    final orderNotice = (saved?.actionKey ?? item.actionKey) == 'site_order_package';
    final packageId = saved?.actionId ?? item.actionId;
    final company = orderNotice ? widget.currentCompany?.call() ?? widget.companyId : null;
    SiteOrderWorkflowApi? orderApi;
    SiteOrderNotificationReadScope? readScope;
    StreamController<void>? orderChanges;
    StreamSubscription<void>? orderSessionChanges;
    VoidCallback? orderListener;
    bool notificationTupleCurrent() {
      final currentIds = snapshot?.notificationIdsByItemKey[item.deduplicationKey] ?? const <String>[];
      if (saved == null) {
        return currentIds.isEmpty && item.actionKey == 'site_order_package' && item.actionId == packageId;
      }
      final current = snapshot?.notificationsById[saved.id];
      return currentIds.isNotEmpty && currentIds.first == saved.id && current != null &&
          current.id == saved.id && current.actionKey == 'site_order_package' &&
          current.actionId == packageId;
    }
    bool retirementQueued = false, flowClosed = false;
    bool flowCurrent() {
      bool current;
      try {
        current = !flowClosed && !_siteOrderBoundaryRetired && mounted && session.isCurrent && capturedLoad == _loadRequest &&
          notificationTupleCurrent() &&
          (widget.currentCompany?.call() ?? widget.companyId) == company &&
          identical(_siteOrderApi, orderApi) && orderApi?.invalidated == false &&
          orderApi?.uiRetired == false && (readScope == null || readScope.isCurrent);
      } catch (_) { current = false; }
      if (!current && !retirementQueued) {
        retirementQueued = true;
        // A getter-only company change has no event stream. Retire at the first
        // scope check, outside the current widget build/event stack.
        scheduleMicrotask(() {
          if (!flowClosed) { readScope?.retire(); orderApi?.retireUiScope(); }
        });
      }
      return current;
    }
    void requireFlow() {
      if (!flowCurrent()) throw StateError('通知一覧から開き直してください。');
      session.requireCurrent();
      orderApi?.requireCurrent();
    }
    setState(() => _opening = true);
    try {
      if (orderNotice) {
        try {
          if (packageId == null || !notificationTargetIsValid('site_order_package', packageId)) {
            throw const SiteOrderNotificationReadUnknown();
          }
          orderApi = widget.siteOrderApiFactory == null
              ? SiteOrderWorkflowRepository.maybeCreate() : widget.siteOrderApiFactory!();
          if (orderApi == null) throw const SiteOrderNotificationReadUnknown();
          _siteOrderBoundaryRetired = false;
          _siteOrderApi = orderApi;
          _siteOrderCompany = company;
          if (!orderApi.bindNotificationUiContext(flowCurrent)) {
            throw const SiteOrderNotificationReadUnknown();
          }
          orderChanges = StreamController<void>.broadcast();
          var invalidationSent = false;
          void emit() {
            if (invalidationSent || orderChanges?.isClosed != false) return;
            invalidationSent = true;
            orderChanges!.add(null);
          }
          orderListener = () { if (orderApi?.invalidated == true || orderApi?.uiRetired == true) emit(); };
          orderApi.addListener(orderListener);
          orderSessionChanges = session.invalidations.listen((_) => emit());
          if (saved != null && saved.id.isNotEmpty) {
            final repository = _notifications;
            if (repository == null) throw const SiteOrderNotificationReadUnknown();
            readScope = repository.openSiteOrderReadScope(api: orderApi,
              notificationId: saved.id, packageId: packageId,
              expectedCompanyId: company,
              currentCompany: company == null ? null : () => widget.currentCompany?.call() ?? widget.companyId);
            _siteOrderRead = readScope;
            readScope.addListener(emit);
            await readScope.verifyTarget();
          } else {
            await verifySiteOrderNotificationTarget(orderApi, packageId);
          }
          requireFlow();
        } catch (error) {
          if (!mounted) return;
          await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) =>
            Scaffold(appBar: AppBar(title: const Text('通知の注文書')),
              body: Center(child: Text(error is SiteOrderNotificationDenied
                ? 'この注文書を閲覧する権限がありません。'
                : '注文書の保存状態を確認できません。通知一覧から確認してください。')))));
          return;
        }
      }
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) =>
        NotificationExplanationPage(item: item,
          isCurrent: orderNotice ? flowCurrent : () => session.isCurrent,
          invalidations: orderNotice ? orderChanges!.stream : session.invalidations,
          onInvalidate: orderNotice ? () => orderApi?.retireUiScope() : session.invalidate,
          onShown: () => _markBodyRead(item, snapshot),
          canOpenTarget: () async {
            session.requireCurrent();
            final ids = snapshot?.notificationIdsByItemKey[item.deduplicationKey] ?? const <String>[];
            final record = ids.isEmpty ? null : snapshot?.notificationsById[ids.first];
            final key = record?.actionKey ?? item.actionKey;
            final id = record?.actionId ?? item.actionId;
            if (!notificationTargetIsValid(key, id)) return false;
            if (key == 'site_order_package') {
              requireFlow();
              if (id != packageId || orderApi == null) return false;
              if (readScope != null) { await readScope.verifyTarget(); }
              else { await verifySiteOrderNotificationTarget(orderApi, id!); }
              requireFlow();
              return true;
            }
            if (SourceNotificationTarget.supports(key)) return true;
            if (record != null && record.kind == 'resident_tax_reminder') {
              if (key != 'payroll_settings' || id == null) return false;
              final repository = SupabaseResidentTaxReminderRepository.maybeCreate();
              if (repository == null) return false;
              await repository.target(record.id, id);
              session.requireCurrent();
              return true;
            }
            final supported = notificationDestination(record ?? AppNotificationRecord(id: '', kind: item.source,
              title: item.title, body: item.body, createdAt: item.createdAt ?? DateTime(1970),
              read: true, actionKey: key, actionId: id)) != null;
            if (!supported) return false;
            if (key == 'company_link_request' && !await companyLinkNotificationAvailable()) return false;
            session.requireCurrent();
            if (key == 'company_profile_review' && !await companyProfileNotificationAvailable()) return false;
            session.requireCurrent();
            final module = notificationModule(key);
            if (module != null) {
              final settings = CompanyModuleSettingsRepository.maybeCreate();
              if (settings == null) return false;
              final states = await settings.loadOptionalModuleStates();
              session.requireCurrent();
              if (states[module] != true) return false;
            }
            return true;
          },
          openTarget: (pageContext) => _openTarget(item, pageContext, snapshot,
            siteOrderApi: orderApi, siteOrderRead: readScope,
            requireSiteOrderCurrent: orderNotice ? requireFlow : null),
        )));
    } finally {
      flowClosed = true;
      if (orderListener != null) orderApi?.removeListener(orderListener);
      await orderSessionChanges?.cancel();
      readScope?.dispose();
      orderApi?.dispose();
      if (identical(_siteOrderRead, readScope)) _siteOrderRead = null;
      if (identical(_siteOrderApi, orderApi)) _siteOrderApi = null;
      await orderChanges?.close();
      if (mounted) {
        setState(() => _opening = false);
      }
    }
    if (mounted && session.isCurrent) await _load();
  }

  Future<void> _markBodyRead(AttentionCenterItem item, AttentionCenterData? snapshot) async {
    final ids = snapshot?.notificationIdsByItemKey[item.deduplicationKey] ?? const <String>[];
    for (final id in ids) {
      final record = snapshot?.notificationsById[id];
      // Link failures stay unread. Only an ordinary notice is read by its body.
      if (record == null || record.read || (record.actionKey?.isNotEmpty ?? false)) continue;
      _session?.requireCurrent();
      final repository = _notifications;
      if (repository == null) throw StateError('Notifications unavailable');
      await repository.markRead(id);
      _session?.requireCurrent();
    }
  }

  Future<void> _openTarget(
    AttentionCenterItem item,
    BuildContext pageContext,
    AttentionCenterData? snapshot, {
    SiteOrderWorkflowApi? siteOrderApi,
    SiteOrderNotificationReadScope? siteOrderRead,
    VoidCallback? requireSiteOrderCurrent,
  }) async {
    _session?.requireCurrent();
    try {
      final data = snapshot;
      final ids =
          data?.notificationIdsByItemKey[item.deduplicationKey] ??
          const <String>[];
      final record = ids.isNotEmpty ? data?.notificationsById[ids.first] : null;
      final target =
          record ??
          AppNotificationRecord(
            id: '',
            kind: item.source,
            title: item.title,
            body: item.body,
            createdAt: item.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
            read: true,
            actionKey: item.actionKey,
            actionId: item.actionId,
          );
      if (!notificationTargetIsValid(target.actionKey, target.actionId)) {
        throw StateError(SkoLanguageController.tr(
          '通知の対象を確認できません。通知一覧を更新して、もう一度お試しください。',
        ));
      }
      if (target.actionKey == 'company_link_request' &&
          !await companyLinkNotificationAvailable()) {
        throw StateError('会社検索・連携申請は現在停止中です');
      }
      if (target.actionKey == 'company_profile_review' &&
          !await companyProfileNotificationAvailable()) {
        throw StateError('会社情報更新確認は現在停止中です');
      }
      final module = notificationModule(target.actionKey);
      if (module != null) {
        final settings = CompanyModuleSettingsRepository.maybeCreate();
        if (settings == null) throw StateError('機能の利用状態を確認できません');
        final states = await settings.loadOptionalModuleStates();
        if (states[module] != true) throw StateError('この機能は現在停止中です');
      }
      DateTime? payrollMonth;
      if (target.actionKey == 'payroll_review') {
        final review = PayrollReviewRepository.maybeCreate();
        if (review == null) {
          throw StateError('Payroll review is unavailable');
        }
        payrollMonth = await review.notificationMonth(target.actionId ?? '');
      }
      Widget? destination;
      if (target.kind == 'resident_tax_reminder') {
        if (target.actionKey != 'payroll_settings' || target.actionId == null) throw StateError('通知の対象を確認できません');
        final repository = SupabaseResidentTaxReminderRepository.maybeCreate();
        if (repository == null) throw StateError('通知の対象を確認できません');
        final saved = await repository.target(target.id, target.actionId!);
        _session?.requireCurrent();
        destination = residentTaxReminderDestination(target, saved);
      } else if (target.actionKey == checkoutReportRegistrationAction && target.actionId != null) {
        final reader = CheckoutReportNotificationRepository.maybeCreate();
        if (reader == null) { throw StateError('通知の日報を確認できません'); }
        await reader.load(target.actionId!); // Authorize before marking the link read.
        _session?.requireCurrent();
        destination = CheckoutReportNotificationPage(reportId: target.actionId!, source: reader);
      } else if (target.actionKey == 'daily_report_edit_request' && target.actionId != null) {
        final client = SupabaseBackend.client;
        final actor = client.auth.currentUser?.id;
        final request = await client.from('daily_report_edit_requests')
            .select('report_id,status,requested_by').eq('id', target.actionId!).maybeSingle();
        if (actor == null || client.auth.currentUser?.id != actor) {
          throw StateError('ログイン状態が変わりました');
        }
        if (request?['status'] == 'approved' && request?['requested_by'] == actor) {
          final report = await client.from('daily_reports')
              .select('id,report_date,site_id,route_assignment_id')
              .eq('id', request!['report_id']).single();
          if (client.auth.currentUser?.id != actor) {
            throw StateError('ログイン状態が変わりました');
          }
          destination = DailyReportPage(
            initialReportId: report['id'] as String,
            initialDate: DateTime.parse(report['report_date'] as String),
            initialSiteId: report['site_id'] as String?,
            initialRouteAssignmentId: report['route_assignment_id'] as String?,
          );
        } else {
          destination = DailyReportApprovalsPage(initialRequestId: target.actionId);
        }
      } else if (target.actionKey == 'site_order_package') {
        if (siteOrderApi == null || target.actionId == null || requireSiteOrderCurrent == null) {
          throw const SiteOrderNotificationReadUnknown();
        }
        requireSiteOrderCurrent();
        if (siteOrderRead != null) { await siteOrderRead.verifyTarget(); }
        else { await verifySiteOrderNotificationTarget(siteOrderApi, target.actionId!); }
        requireSiteOrderCurrent();
        final capturedId = record?.id, capturedPackage = target.actionId;
        destination = SiteOrderSiteActionsPage.notification(api: siteOrderApi,
          packageId: target.actionId!,
          onNotificationRead: siteOrderRead == null ? null : (requireOwnedScope) async {
            void requireTuple() {
              requireOwnedScope(); requireSiteOrderCurrent();
              final current = capturedId == null ? null : data?.notificationsById[capturedId];
              if (current == null || current.id != siteOrderRead.notificationId ||
                  current.actionKey != 'site_order_package' || current.actionId != capturedPackage ||
                  capturedPackage != siteOrderRead.packageId) {
                throw const SiteOrderNotificationReadUnknown();
              }
            }
            requireTuple();
            await siteOrderRead.markRead(requireTuple);
            requireTuple();
          });
      } else if (SourceNotificationTarget.supports(target.actionKey)) {
        final repository = _notifications;
        if (repository == null) {
          throw StateError('Notifications unavailable');
        }
        final savedTarget = await repository.sourceTarget(target);
        destination = SourceNotificationTargetPage(target: savedTarget);
      } else {
        destination = notificationDestination(
          target,
          payrollMonth: payrollMonth,
        );
      }
      if (!mounted) {
        return;
      }
      if (destination == null && target.actionKey != null) {
        if (!pageContext.mounted) return;
        ScaffoldMessenger.of(pageContext).showSnackBar(
          SnackBar(content: Text(SkoLanguageController.tr('関連画面への案内を準備しています'))),
        );
        return;
      }
      _session?.requireCurrent();
      // System tasks have no notification id and never write a synthetic read state.
      if (target.actionKey != 'site_order_package') {
        for (final id in ids) {
          _session?.requireCurrent();
          if (data?.notificationsById[id]?.read == false) {
            await _notifications?.markRead(id);
          }
        }
      }
      if (!mounted) {
        return;
      }
      _session?.requireCurrent();
      final page = destination;
      if (page != null) {
        if (!pageContext.mounted) return;
        await Navigator.of(pageContext)
            .push(MaterialPageRoute<void>(builder: (_) => page));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(SkoLanguageController.tr('お知らせを確認しました'))),
        );
      }
      if (mounted) {
        await _load();
      }
    } catch (error) {
      _showError(error);
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    final data = _data;
    bool unread(AttentionCenterItem item) =>
        (data?.notificationIdsByItemKey[item.deduplicationKey] ?? const <String>[])
            .any((id) => data?.notificationsById[id]?.read == false);
    final visible = data?.snapshot.items
        .where((item) => !_pendingOnly || item.needsAction).toList() ??
        <AttentionCenterItem>[];
    // Stable partition: retain existing task/deadline order within each section.
    final items = [
      ...visible.where(unread),
      ...visible.where((item) => !unread(item)),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(
          SkoLanguageController.tr('お知らせ'),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          if (data?.notificationsById.values.any((item) => !item.read) == true)
            TextButton(
              onPressed: _opening ? null : _markAll,
              child: Text(SkoLanguageController.tr('すべて既読')),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: SegmentedButton<bool>(
                segments: [
                  ButtonSegment(
                    value: false,
                    label: Text(SkoLanguageController.tr('すべて')),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text(SkoLanguageController.tr('要対応')),
                  ),
                ],
                selected: {_pendingOnly},
                onSelectionChanged: (values) =>
                    setState(() => _pendingOnly = values.single),
              ),
            ),
            if (data?.unavailableSources.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Text(
                  SkoLanguageController.tr('一部のお知らせを取得できません。再読み込みしてください。'),
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(SkoLanguageController.tr(_error!)),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(12),
                        children: [
                          if (items.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(24),
                              child: Center(
                                child: Text(
                                  SkoLanguageController.tr(
                                    _pendingOnly
                                        ? '未対応の項目はありません'
                                        : '新しいお知らせはありません',
                                  ),
                                ),
                              ),
                            ),
                          for (final item in items)
                            Card(
                              color: unread(item)
                                  ? Theme.of(context).colorScheme.primaryContainer
                                  : null,
                              child: ListTile(
                                leading: CircleAvatar(
                                  child: Icon(
                                    item.needsAction
                                        ? Icons.notifications_active_outlined
                                        : Icons.notifications_outlined,
                                  ),
                                ),
                                title: Text(
                                  _isSiteOrderItem(item) ? '注文・請書のお知らせ' : item.title,
                                  style: TextStyle(
                                    fontWeight: item.needsAction || !item.read
                                        ? FontWeight.w900
                                        : FontWeight.w600,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (unread(item))
                                      Text(SkoLanguageController.tr('未読'),
                                        style: const TextStyle(fontWeight: FontWeight.w900)),
                                    if (_isSiteOrderItem(item))
                                      const Text('保存書類と現在の閲覧権限を確認して開きます。')
                                    else ...[
                                      if (item.body.isNotEmpty) Text(item.body),
                                      if (item.state != AttentionCenterState.information)
                                        Text(_businessDescription(item)),
                                    ],
                                    if (item.createdAt != null)
                                      Text(
                                        _formatDate(item.createdAt!),
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                  ],
                                ),
                                trailing:
                                    unread(item)
                                    ? const Badge(
                                        child: Icon(Icons.chevron_right),
                                      )
                                    : const Icon(Icons.chevron_right),
                                onTap: _opening ? null : () => _open(item),
                              ),
                            ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isSiteOrderItem(AttentionCenterItem item) {
    final ids = _data?.notificationIdsByItemKey[item.deduplicationKey] ?? const <String>[];
    final record = ids.isEmpty ? null : _data?.notificationsById[ids.first];
    return (record?.actionKey ?? item.actionKey) == 'site_order_package';
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
    final targetDate = date == null
        ? null
        : item.actionKey == 'payroll_review' ||
              item.actionKey == 'invoice_approval'
        ? '${date.year}/${date.month.toString().padLeft(2, '0')}'
        : '${date.year}/${date.month}/${date.day}';
    return [
      if (item.targetName?.isNotEmpty == true) item.targetName!,
      if (targetDate != null) targetDate,
      SkoLanguageController.tr(label),
    ].join(' / ');
  }

  String _formatDate(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${value.year}/${two(value.month)}/${two(value.day)} ${two(value.hour)}:${two(value.minute)}';
  }
}

/// Known notification routes reuse the same protected pages as the home menu.
/// Repositories in each destination retain their existing access checks and RLS.
Widget? notificationDestination(
  AppNotificationRecord item, {
  DateTime? payrollMonth,
  @visibleForTesting SiteOrderWorkflowApi? siteOrderApi,
}) {
  if (item.kind == 'resident_tax_reminder') return null; // Requires server-authorized annual target.
  if (!notificationTargetIsValid(item.actionKey, item.actionId)) return null;
  return switch (item.actionKey) {
  'site_order_package' => SiteOrderSiteActionsPage.notification(
    api: siteOrderApi, packageId: item.actionId!),
  'site_payment_agreement' => SiteContractNotificationPage(notificationId: item.id),
  'company_link_request' => companyLinkNotificationDestination(item.actionId),
  'company_profile_review' => item.actionId == null || item.actionId!.isEmpty
      ? null
      : CompanyProfileReviewPage(initialReviewId: item.actionId),
  'qualification_photo_request' => const QualificationPhotoSubmissionReviewPage(),
  'route_billing_quantity_request' => RouteBillingQuantityApprovalsPage(
    initialRequestId: item.actionId,
  ),
  'attendance_today' => AttendanceNotificationPage(verificationId: item.actionId ?? ''),
  'document_register' => const OwnDocumentRegistrationPage(),
  'chat_group_invite' => ChatCloudPage(
    showGroupsInitially: true,
    initialInviteId: item.actionId ?? '',
  ),
  'site_map' => SiteMapNotificationPage(verificationId: item.actionId ?? ''),
  'site_share_approval' => SiteShareApprovalPage(
    initialRequestId: item.actionId,
  ),
  'site_information_request' || 'site_information_request_result' =>
    SiteInformationApprovalsPage(initialRequestId: item.actionId),
  'vehicle_documents' => VehicleRoutePage(initialVehicleId: item.actionId ?? ''),
  'checkout_report_registration' => CheckoutReportNotificationPage(reportId: item.actionId!),
  'daily_report_edit_request' => DailyReportApprovalsPage(
    initialRequestId: item.actionId,
  ),
  'paid_leave_request' => PaidLeaveApprovalsPage(
    initialRequestId: item.actionId,
  ),
  'attendance_correction_request' => AttendanceCorrectionApprovalsPage(
    initialRequestId: item.actionId,
  ),
  'worker_personnel_change' => WorkerPersonnelChangeApprovalsPage(
    initialRequestId: item.actionId,
  ),
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
  'invoice_approval' => InvoiceNotificationPage(invoiceId: item.actionId ?? '', notificationId: item.id),
  'payment_certificate_settings' => SecondaryProtectedPage(
    title: SkoLanguageController.tr('支払証明書設定'),
    child: const PartnerPaymentSettingsPage(),
  ),
  'master_security_incident' => MasterProtectedPage(
    title: 'セキュリティ記録',
    child: SecurityActorBoundary(
      child: SecurityIncidentPage(incidentId: item.actionId),
    ),
  ),
  'expense_review_request' || 'expense_review_completed' => ExpenseNotificationPage(
    notificationId: item.id, actionKey: item.actionKey!, actionId: item.actionId!,
  ),
  'settings' => const SettingsPage(),
  _ => null,
  };
}

/// Recheck optional modules when following a historical notice, not only on home.
String? notificationModule(String? actionKey) => switch (actionKey) {
  'document_register' => 'documents',
  'chat_group_invite' => 'chat',
  'site_map' ||
  'site_share_approval' ||
  'site_information_request' ||
  'site_information_request_result' ||
  'admin_sites' ||
  'site_payment_agreement' => 'sites',
  'vehicle_documents' => 'vehicle_routes',
  'invoice_approval' || 'route_billing_quantity_request' => 'invoices',
  'attendance_today' ||
  'paid_leave_request' ||
  'attendance_correction_request' => 'attendance',
  _ => null,
};

/// The server workspace checks current membership and account availability.
Future<bool> companyProfileNotificationAvailable() async {
  if (!SupabaseBackend.isInitialized ||
      SupabaseBackend.client.auth.currentUser == null) {
    return false;
  }
  final raw = await SupabaseBackend.client.rpc('company_profile_review_workspace');
  return raw is Map && raw['enabled'] == true;
}

/// Both checks use the server workspace so OFF and changed roles fail closed.
Future<bool> companyLinkNotificationAvailable() async {
  final repository = TradeCompanyRepository.maybeCreate();
  if (repository == null) return false;
  final scope = repository.createLinkScope();
  try {
    await scope.loadContexts();
    return scope.contexts.any((company) => company.enabled);
  } finally {
    await scope.close();
  }
}

Widget? companyLinkNotificationDestination(String? requestId) {
  final repository = TradeCompanyRepository.maybeCreate();
  if (repository == null || requestId == null || requestId.isEmpty) return null;
  return CompanyLinkPage(
    repository: repository,
    mode: TradeCompanyPageMode.customer,
    initialRequestId: requestId,
  );
}

/// Only a saved, company-checked reminder may open the annual page.
Widget residentTaxReminderDestination(AppNotificationRecord item, ResidentTaxReminderTarget target) {
  if (item.kind != 'resident_tax_reminder' || item.actionKey != 'payroll_settings' || item.actionId != target.companyId) {
    throw const FormatException('通知と年度更新の会社が一致しません');
  }
  return SecondaryProtectedPage(title: '住民税の年度一括更新', child: ResidentTaxAnnualUpdatePage(
    companyId: target.companyId, fiscalYear: target.fiscalYear,
    reminderPanel: ResidentTaxReminderPanel(companyId: target.companyId),
  ));
}
