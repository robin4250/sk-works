import 'package:flutter/material.dart';

import 'site_order_outgoing_compose_page.dart';
import 'site_order_workflow_page.dart';
import 'site_order_workflow_repository.dart';

class SiteOrderNotificationDenied implements Exception {
  const SiteOrderNotificationDenied();
}

/// Checks a saved package, never a guessed local site. No generation gate or
/// mutation is called; current server read authorization remains mandatory.
Future<void> verifySiteOrderNotificationTarget(
    SiteOrderWorkflowApi api, String packageId) async {
  if (!RegExp(r'^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$').hasMatch(packageId)) {
    throw StateError('通知の対象を確認できません。');
  }
  void requireCurrent() {
    if (api.uiRetired || api.invalidated) throw StateError('通知を開き直してください。');
    api.requireCurrent();
  }
  // A fresh repository's captured gateway epoch is admitted by verify().
  // Do not call its synchronous requireCurrent before that admission.
  if (api.uiRetired || api.invalidated) throw StateError('通知を開き直してください。');
  await api.verify();
  requireCurrent();
  final detail = await api.detail(packageId);
  requireCurrent();
  await api.verify();
  requireCurrent();
  if (detail['package_id'] != packageId) throw const SiteOrderNotificationDenied();
  if (detail['is_sender'] is! bool || detail['is_recipient'] is! bool) {
    throw StateError('通知の保存対象を確認できません。');
  }
  if (detail['is_sender'] == false && detail['is_recipient'] == false) {
    throw const SiteOrderNotificationDenied();
  }
}

/// Owns only this site's order routes. Retiring it never cancels server work or
/// deletes a journal; an uncertain operation must be reconciled on reopening.
class SiteOrderSiteActionsPage extends StatefulWidget {
  const SiteOrderSiteActionsPage({
    super.key,
    required this.siteId,
    required this.siteName,
    this.api,
  }) : packageId = null, onNotificationRead = null;
  const SiteOrderSiteActionsPage.notification({
    super.key,
    required String this.packageId,
    this.api,
    this.onNotificationRead,
  }) : siteId = '', siteName = '';
  final String siteId, siteName;
  final String? packageId;
  final Future<void> Function(VoidCallback requireOwnedScope)? onNotificationRead;
  @visibleForTesting
  final SiteOrderWorkflowApi? api;

  @override
  State<SiteOrderSiteActionsPage> createState() => _SiteOrderSiteActionsPageState();
}

class _SiteOrderSiteActionsPageState extends State<SiteOrderSiteActionsPage>
    with WidgetsBindingObserver {
  final _navigator = GlobalKey<NavigatorState>();
  final _changes = ValueNotifier<int>(0);
  late final SiteOrderWorkflowApi? _api;
  late final bool _ownsApi;
  late final String _siteId, _siteName;
  late final String? _packageId;
  bool _notificationAdmitted = false, _readInvoked = false;
  bool _notificationDenied = false, _readUnknown = false;
  bool _busy = true, _retired = false, _canCreate = false, _available = false;
  bool _closing = false, _handlingBack = false;
  int _generation = 0;
  String? _error;
  ModalRoute<dynamic>? _ownerRoute;
  NavigatorState? _ownerNavigator;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _siteId = widget.siteId;
    _siteName = widget.siteName;
    _packageId = widget.packageId;
    _ownsApi = widget.api == null;
    _api = widget.api ?? SiteOrderWorkflowRepository.maybeCreate();
    _api?.addListener(_changed);
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ownerRoute ??= ModalRoute.of(context);
    _ownerNavigator ??= Navigator.of(context);
  }

  void _update(VoidCallback change) {
    setState(change);
    _changes.value++;
  }

  void _require() {
    if (_retired || _closing || _api == null || _api.uiRetired) {
      throw StateError('現場を開き直してください。');
    }
    _api.requireCurrent();
  }

  void _changed() {
    if (_api?.invalidated == true) _retire();
  }

  void _retire() {
    if (_retired) return;
    _retired = true;
    _generation++;
    _canCreate = false;
    _available = false;
    _api?.retireUiScope();
    FocusManager.instance.primaryFocus?.unfocus();
    if (mounted) _update(() {});
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final api = _api;
    try {
      if (!RegExp(r'^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$').hasMatch(_packageId ?? _siteId)) {
        _retire();
        return;
      }
      if (api == null) {
        throw StateError('現場・ログイン状態を確認してください。');
      }
      if (!await api.canUseWorkflow()) {
        throw StateError('現場の注文・請書機能は準備中です。');
      }
      _require();
      _available = true;
      if (_packageId != null) {
        await verifySiteOrderNotificationTarget(api, _packageId);
        _require();
        final read = widget.onNotificationRead;
        if (read != null && !_readInvoked) {
          _readInvoked = true;
          try { await read(_require); }
          catch (_) { _readUnknown = true; }
          _require();
        }
        if (!mounted || generation != _generation) return;
        _update(() { _notificationAdmitted = true; _error = null; });
        return;
      }
      await api.verify();
      _require();
      final allowed = await api.canCreateOutgoing();
      _require();
      if (!mounted || generation != _generation) return;
      _update(() { _canCreate = allowed; _error = null; });
    } on SiteOrderNotificationDenied {
      if (mounted && !_retired && generation == _generation) {
        _update(() { _notificationDenied = true; _error = 'この注文書を閲覧する権限がありません。'; });
      }
    } catch (_) {
      if (mounted && !_retired && generation == _generation) {
        _update(() => _error = '注文書の利用状態を確認できません。保存状態から確認してください。');
      }
    } finally {
      if (mounted && generation == _generation) _update(() => _busy = false);
    }
  }

  Future<void> _open(String action) async {
    if (_busy || _retired || _closing) return;
    final api = _api, navigator = _navigator.currentState;
    if (api == null || navigator == null) return;
    _update(() => _busy = true);
    try {
      await api.verify();
      _require();
      if (!await api.canUseWorkflow()) {
        if (mounted) _update(() { _available = false; _canCreate = false; _error = '現場の注文・請書機能は準備中です。'; });
        return;
      }
      _require();
      if (action == 'create' && !await api.canCreateOutgoing()) {
        _require();
        if (mounted) _update(() => _canCreate = false);
        return;
      }
      _require();
      if (!mounted || !navigator.mounted) return;
      final page = action == 'create'
          ? SiteOrderOutgoingComposePage(api: api, siteId: _siteId,
              issueDate: DateTime.now().toIso8601String().substring(0, 10))
          : SiteOrderWorkflowPage(api: api, siteId: _siteId, siteName: _siteName,
              historyTitle: action == 'view' ? '保存された注文書を選択'
                : action == 'warehouse' ? '$_siteNameの管理倉庫（注文書・請書）' : null);
      // _busy protects admission only; the owned child manages its own writes.
      if (mounted) _update(() => _busy = false);
      await navigator.push<void>(MaterialPageRoute(builder: (_) => page));
      _require();
    } catch (_) {
      if (mounted && !_retired) {
        _update(() => _error = '注文書を確認できません。現場から開き直してください。');
      }
    } finally {
      if (mounted && !_retired) _update(() => _busy = false);
    }
  }

  void _closeHost() {
    final owner = _ownerNavigator, route = _ownerRoute;
    if (_closing || owner == null || route == null || !owner.mounted ||
        !identical(ModalRoute.of(context), route) ||
        !identical(Navigator.of(context), owner) || !route.isCurrent || !owner.canPop()) {
      return;
    }
    _update(() => _closing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // A root dialog can appear between the button and this frame. Never pop
      // whichever unrelated route happens to be on top at that time.
      if (!mounted || !owner.mounted ||
          !identical(ModalRoute.of(context), route) ||
          !identical(Navigator.of(context), owner) || !route.isCurrent || !owner.canPop()) {
        if (mounted) _update(() => _closing = false);
        return;
      }
      owner.pop();
    });
  }

  Future<void> _back(bool didPop) async {
    if (didPop || _handlingBack || _closing) return;
    _handlingBack = true;
    try {
      final navigator = _navigator.currentState;
      if (!_retired && navigator != null && navigator.canPop()) {
        await navigator.maybePop();
      } else {
        _closeHost();
      }
    } finally {
      _handlingBack = false;
    }
  }

  @override
  void didUpdateWidget(covariant SiteOrderSiteActionsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.api != widget.api || oldWidget.siteId != widget.siteId ||
        oldWidget.siteName != widget.siteName ||
        oldWidget.packageId != widget.packageId ||
        oldWidget.onNotificationRead != widget.onNotificationRead) {
      _retire();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _retire();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _api?.removeListener(_changed);
    _api?.retireUiScope();
    if (_ownsApi) _api?.dispose();
    _changes.dispose();
    super.dispose();
  }

  Widget _menu() => Scaffold(
    appBar: AppBar(title: Text(_siteName), leading: IconButton(
      tooltip: '閉じる', onPressed: _closing ? null : () => _closeHost(),
      icon: const Icon(Icons.close))),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      if (_busy) const LinearProgressIndicator(),
      if (_error != null) Text(_error!),
      OutlinedButton(onPressed: _busy || !_available ? null : () => _open('view'),
        child: const Text('注文書を見る')),
      const Text('工事名称と工期を確認して、保存済みの原本を選択します。'),
      FilledButton(onPressed: _busy || !_canCreate ? null : () => _open('create'),
        child: const Text('注文書を作る')),
      if (!_busy && !_canCreate) const Text('現場の注文・請書機能は準備中です。'),
      OutlinedButton.icon(onPressed: _busy || !_available ? null : () => _open('warehouse'),
        icon: const Icon(Icons.inventory_2_outlined),
        label: const Text('管理倉庫（注文書・請書）')),
      const Text('この現場の注文書と、相手会社から返送された請書を取引ごとに確認・PDF保存・印刷できます。'),
      OutlinedButton(onPressed: _busy || !_available ? null : () => _open('history'),
        child: const Text('過去の注文書')),
    ]),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _closing,
    onPopInvokedWithResult: (didPop, _) => _back(didPop),
    child: _retired
        ? Scaffold(appBar: AppBar(title: const Text('現場の注文書'),
            leading: IconButton(tooltip: '閉じる', icon: const Icon(Icons.close),
              onPressed: () => _closeHost())),
            body: const Center(child: Text('ログイン・会社・現場の状態が変わりました。開き直してください。')))
        : _packageId != null && !_notificationAdmitted
            ? Scaffold(appBar: AppBar(title: const Text('通知の注文書'),
                leading: IconButton(tooltip: '閉じる', icon: const Icon(Icons.close),
                  onPressed: () => _closeHost())),
                body: Center(child: _busy ? const CircularProgressIndicator()
                  : Text(_notificationDenied ? 'この注文書を閲覧する権限がありません。'
                    : '注文書の保存状態を確認できません。通知一覧から確認してください。')))
            : Column(children: [
                if (_readUnknown) const Text('既読の記録を確認できません。'),
                Expanded(child: Navigator(key: _navigator,
                  onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) =>
                    _packageId != null
                      ? SiteOrderWorkflowPage(api: _api, initialPackageId: _packageId)
                      : AnimatedBuilder(animation: _changes,
                          builder: (_, __) => _menu())))),
              ]),
  );
}
