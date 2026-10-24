import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/supabase_backend.dart';
import '../settings/company_allowance_identity_page.dart';
import 'company_common_payroll_page.dart';

class CompanyCommonAllowanceScope {
  const CompanyCommonAllowanceScope(this.companyId, this.name, this.canEdit);
  final String companyId;
  final String name;
  final bool canEdit;
}

/// Allowance-only scope entry, narrowed from the reviewed PR1156 selector.
/// Company data does not expose a second allowance editor. Registered-item
/// management remains available inside this payroll-list entry.
/// Membership hints only select the scope; each child RPC authorizes it again.
class CompanyCommonAllowanceEntryPage extends StatefulWidget {
  const CompanyCommonAllowanceEntryPage({super.key, this.companyId,
    this.scopeLoader, this.currentActor, this.allowancesBuilder});
  final String? companyId;
  @visibleForTesting final Future<List<CompanyCommonAllowanceScope>> Function()? scopeLoader;
  @visibleForTesting final String? Function()? currentActor;
  @visibleForTesting final Widget Function(BuildContext, String)? allowancesBuilder;
  @override
  State<CompanyCommonAllowanceEntryPage> createState() => _CompanyCommonAllowanceEntryPageState();
}

class _CompanyCommonAllowanceEntryPageState extends State<CompanyCommonAllowanceEntryPage>
    with WidgetsBindingObserver {
  StreamSubscription<dynamic>? _auth;
  String? _actor;
  CompanyCommonAllowanceScope? _selected;
  List<CompanyCommonAllowanceScope> _choices = const [];
  bool _foreground = false;
  bool _verified = false;
  bool _loading = false;
  bool _invalidated = false;
  String? _error;
  int _generation = 0;
  int _editorEpoch = 0;

  String? get _currentActor => widget.currentActor != null
      ? widget.currentActor!()
      : (SupabaseBackend.isInitialized ? SupabaseBackend.client.auth.currentUser?.id : null);

  @override
  void initState() {
    super.initState();
    _actor = _currentActor;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    if (SupabaseBackend.isInitialized && widget.currentActor == null) {
      _auth = SupabaseBackend.client.auth.onAuthStateChange.listen((state) {
        if (state.session?.user.id != _actor) _invalidate();
      }, onError: (_) => _invalidate());
    }
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant CompanyCommonAllowanceEntryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.companyId != widget.companyId) {
      _generation++;
      _selected = null;
      _choices = const [];
      _verified = false;
      _editorEpoch++;
      unawaited(_load());
    }
  }

  void _invalidate() {
    if (!mounted) return;
    _generation++;
    setState(() {
      _invalidated = true; _verified = false; _selected = null;
      _choices = const []; _loading = false; _editorEpoch++;
      _error = 'ログイン状態が変わりました。この画面を開き直してください。';
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _generation++;
      setState(() { _verified = false; _loading = false; });
    } else {
      unawaited(_load());
    }
  }

  Future<List<CompanyCommonAllowanceScope>> _loadMemberships() async {
    if (!SupabaseBackend.isInitialized) throw StateError('Cloud unavailable');
    final client = SupabaseBackend.client;
    final session = client.auth.currentSession;
    if (session == null || session.user.id != _actor) throw StateError('Actor changed');
    final rows = await client.from('company_members')
        .select('company_id, role, companies(name)').eq('user_id', session.user.id)
        .inFilter('role', ['owner', 'admin', 'viewer'])
        .setHeader('Authorization', 'Bearer ${session.accessToken}');
    return [for (final row in rows)
      if (row['company_id'] is String && const ['owner', 'admin', 'viewer'].contains(row['role']))
        CompanyCommonAllowanceScope(row['company_id'] as String,
          row['companies'] is Map ? (row['companies']['name']?.toString() ?? '登録会社') : '登録会社',
          row['role'] == 'owner' || row['role'] == 'admin')];
  }

  Future<void> _load() async {
    if (!_foreground || _invalidated || !mounted) return;
    if (_actor == null || _currentActor != _actor) { _invalidate(); return; }
    final generation = ++_generation;
    setState(() { _loading = true; _verified = false; _error = null; });
    bool current() => mounted && !_invalidated && generation == _generation &&
        _foreground && _currentActor == _actor;
    try {
      final scopes = await (widget.scopeLoader?.call() ?? _loadMemberships());
      if (!current()) {
        if (mounted && !_invalidated && _currentActor != _actor) _invalidate();
        return;
      }
      final requested = widget.companyId ?? _selected?.companyId;
      CompanyCommonAllowanceScope? selected;
      if (requested != null) {
        for (final scope in scopes) {
          if (scope.companyId == requested) selected = scope;
        }
      } else if (scopes.length == 1) {
        selected = scopes.single;
      }
      setState(() {
        if (requested != null && selected == null) {
          _editorEpoch++; _error = 'この会社の設定を表示する権限を確認できません。';
        } else if (_selected != null && selected != null &&
            _selected!.canEdit != selected.canEdit) {
          _editorEpoch++;
        }
        _selected = selected; _choices = List.unmodifiable(scopes);
        _verified = true; _loading = false;
        if (scopes.isEmpty) _error = '表示できる会社の設定がありません。';
      });
    } catch (_) {
      if (!current()) {
        if (mounted && !_invalidated && _currentActor != _actor) _invalidate();
        return;
      }
      setState(() { _loading = false; _error = '会社・権限を確認できません。入力内容は保持しています。'; });
    }
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_auth?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final covered = !_foreground || !_verified || _invalidated;
    final content = Scaffold(
      appBar: selected == null ? AppBar(title: const Text('社内共通手当')) : null,
      body: selected == null ? ListView(padding: const EdgeInsets.all(16), children: [
        if (_error != null) Text(_error!),
        if (_choices.length > 1) const Text('設定する会社を選択してください。'),
        for (final scope in _choices) ListTile(title: Text(scope.name),
          subtitle: Text(scope.canEdit ? '管理者' : '閲覧のみ'),
          onTap: () => setState(() { _selected = scope; _error = null; _editorEpoch++; })),
      ]) : Column(children: [
        Expanded(child: KeyedSubtree(key: ValueKey('${selected.companyId}/$_editorEpoch'), child:
          widget.allowancesBuilder?.call(context, selected.companyId) ??
            CompanyCommonPayrollPage(companyId: selected.companyId))),
        if (selected.canEdit) SafeArea(top: false, child: TextButton(
          key: const ValueKey('common-allowance-registered-items'),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => CompanyAllowanceIdentityPage(companyId: selected.companyId))),
          child: const Text('登録済み項目管理'),
        )),
      ]),
    );
    return Stack(children: [
      Offstage(offstage: covered, child: content),
      if (covered) Scaffold(appBar: AppBar(title: const Text('社内共通手当')),
        body: Center(child: _loading ? const CircularProgressIndicator() : Column(
          mainAxisSize: MainAxisSize.min, children: [
            Text(_error ?? '会社・権限を確認しています。'),
            if (_foreground && !_invalidated) TextButton(onPressed: _load, child: const Text('再確認')),
          ]))),
    ]);
  }
}
