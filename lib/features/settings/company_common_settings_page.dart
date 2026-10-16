import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/supabase_backend.dart';
import '../payroll/company_common_payroll_page.dart';
import 'company_common_tax_page.dart';

class CompanyCommonSettingsScope {
  const CompanyCommonSettingsScope(this.companyId, this.name, this.canEdit);
  final String companyId;
  final String name;
  final bool canEdit;
}

/// Both entry points select a company, then use the same authoritative settings.
/// Membership hints only select the scope; each child RPC authorizes it again.
class CompanyCommonSettingsPage extends StatefulWidget {
  const CompanyCommonSettingsPage({super.key, this.companyId,
    this.scopeLoader, this.currentActor, this.allowancesBuilder, this.taxBuilder});
  final String? companyId;
  @visibleForTesting final Future<List<CompanyCommonSettingsScope>> Function()? scopeLoader;
  @visibleForTesting final String? Function()? currentActor;
  @visibleForTesting final Widget Function(BuildContext, String)? allowancesBuilder;
  @visibleForTesting final Widget Function(BuildContext, String)? taxBuilder;
  @override
  State<CompanyCommonSettingsPage> createState() => _CompanyCommonSettingsPageState();
}

class _CompanyCommonSettingsPageState extends State<CompanyCommonSettingsPage>
    with WidgetsBindingObserver {
  StreamSubscription<dynamic>? _auth;
  String? _actor;
  CompanyCommonSettingsScope? _selected;
  List<CompanyCommonSettingsScope> _choices = const [];
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
  void didUpdateWidget(covariant CompanyCommonSettingsPage oldWidget) {
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

  Future<List<CompanyCommonSettingsScope>> _loadMemberships() async {
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
        CompanyCommonSettingsScope(row['company_id'] as String,
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
      CompanyCommonSettingsScope? selected;
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
            _selected!.canEdit != selected!.canEdit) {
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

  void _help() => showDialog<void>(context: context, builder: (context) => AlertDialog(
    title: const Text('会社共通設定'),
    content: const Text('手当は「時給・日給・月給」「時間・日・月単位」「支給・控除」で切り替え、追加・編集・削除します。元からある3枠は日単位の支給の先頭に残し、同じ会社データを使います。消費税・福利厚生費もこの設定内で管理します。保存が確認できた時だけ完了を表示します。結果不明時は再送せず保存状態を確認してください。共通項目の個別給料設定・計算・明細への接続は、接続確認が済むまで完了扱いにしません。'),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('閉じる'))]));

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final covered = !_foreground || !_verified || _invalidated;
    final content = DefaultTabController(length: 2, child: Scaffold(
      appBar: AppBar(title: const Text('会社共通設定'), actions: [
        IconButton(tooltip: '会社共通設定の使い方', onPressed: _help, icon: const Icon(Icons.help_outline)),
      ], bottom: selected == null ? null : const TabBar(tabs: [
        Tab(text: '手当'), Tab(text: '消費税・福利厚生費'),
      ])),
      body: selected == null ? ListView(padding: const EdgeInsets.all(16), children: [
        if (_error != null) Text(_error!),
        if (_choices.length > 1) const Text('設定する会社を選択してください。'),
        for (final scope in _choices) ListTile(title: Text(scope.name),
          subtitle: Text(scope.canEdit ? '管理者' : '閲覧のみ'),
          onTap: () => setState(() { _selected = scope; _error = null; _editorEpoch++; })),
      ]) : Builder(key: ValueKey('${selected.companyId}/$_editorEpoch'), builder: (context) {
        final tabs = DefaultTabController.of(context);
        return AnimatedBuilder(animation: tabs, builder: (_, __) => IndexedStack(index: tabs.index, children: [
        widget.allowancesBuilder?.call(context, selected.companyId) ??
            CompanyCommonPayrollPage(companyId: selected.companyId, embedded: true),
        widget.taxBuilder?.call(context, selected.companyId) ??
            CompanyCommonTaxPage(companyId: selected.companyId, embedded: true),
      ]));
      }),
    ));
    return Stack(children: [
      Offstage(offstage: covered, child: content),
      if (covered) Scaffold(appBar: AppBar(title: const Text('会社共通設定')),
        body: Center(child: _loading ? const CircularProgressIndicator() : Column(
          mainAxisSize: MainAxisSize.min, children: [
            Text(_error ?? '会社・権限を確認しています。'),
            if (_foreground && !_invalidated) TextButton(onPressed: _load, child: const Text('再確認')),
          ]))),
    ]);
  }
}
