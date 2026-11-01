import 'package:flutter/material.dart';

import 'site_order_outgoing_compose_page.dart';
import 'site_order_workflow_page.dart';
import 'site_order_workflow_repository.dart';

/// Owns only this site's order routes. Retiring it never cancels server work or
/// deletes a journal; an uncertain operation must be reconciled on reopening.
class SiteOrderSiteActionsPage extends StatefulWidget {
  const SiteOrderSiteActionsPage({
    super.key,
    required this.siteId,
    required this.siteName,
    this.api,
  });
  final String siteId, siteName;
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
  bool _busy = true, _retired = false, _canCreate = false;
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
    if (_retired || _closing || _api == null || _api!.uiRetired) {
      throw StateError('現場を開き直してください。');
    }
    _api!.requireCurrent();
  }

  void _changed() {
    if (_api?.invalidated == true) _retire();
  }

  void _retire() {
    if (_retired) return;
    _retired = true;
    _generation++;
    _canCreate = false;
    _api?.retireUiScope();
    FocusManager.instance.primaryFocus?.unfocus();
    if (mounted) _update(() {});
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final api = _api;
    try {
      if (!RegExp(r'^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$').hasMatch(_siteId)) {
        _retire();
        return;
      }
      if (api == null) {
        throw StateError('現場・ログイン状態を確認してください。');
      }
      await api.verify();
      _require();
      final allowed = await api.canCreateOutgoing();
      _require();
      if (!mounted || generation != _generation) return;
      _update(() { _canCreate = allowed; _error = null; });
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
              historyTitle: action == 'view' ? '保存された注文書を選択' : null);
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

  void _closeHost([bool editFinancial = false]) {
    if (editFinancial && (_retired || _api?.invalidated != false)) return;
    final owner = _ownerNavigator, route = _ownerRoute;
    if (_closing || owner == null || route == null || !owner.mounted ||
        !identical(ModalRoute.of(context), route) ||
        !identical(Navigator.of(context), owner) || !route.isCurrent || !owner.canPop()) return;
    _update(() => _closing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // A root dialog can appear between the button and this frame. Never pop
      // whichever unrelated route happens to be on top at that time.
      if (!mounted || !owner.mounted ||
          (editFinancial && (_retired || _api?.invalidated != false)) ||
          !identical(ModalRoute.of(context), route) ||
          !identical(Navigator.of(context), owner) || !route.isCurrent || !owner.canPop()) {
        if (mounted) _update(() => _closing = false);
        return;
      }
      owner.pop(editFinancial);
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
        oldWidget.siteName != widget.siteName) _retire();
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
      OutlinedButton(onPressed: _busy ? null : () => _open('view'),
        child: const Text('注文書を見る')),
      const Text('保存済みの原本を一覧から選びます。最新の注文を推測して開くことはありません。'),
      FilledButton(onPressed: _busy || !_canCreate ? null : () => _open('create'),
        child: const Text('注文書を作る')),
      if (!_busy && !_canCreate) const Text('現在、新規作成は利用できません。'),
      OutlinedButton(onPressed: _busy ? null : () => _open('history'),
        child: const Text('過去の注文書')),
      const Divider(),
      OutlinedButton(onPressed: _busy ? null : () => _closeHost(true),
        child: const Text('現場の金額設定')),
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
        : Navigator(key: _navigator, onGenerateRoute: (_) => MaterialPageRoute<void>(
            builder: (_) => AnimatedBuilder(animation: _changes,
              builder: (_, __) => _menu()))),
  );
}
