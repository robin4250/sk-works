import 'package:flutter/material.dart';
import 'expense_claim.dart';
import 'expense_claims_page.dart';
import 'expense_management_repository.dart';

class ExpenseManagementPage extends StatefulWidget {
  const ExpenseManagementPage({super.key, this.access});
  final ExpenseManagementAccess? access;
  @override
  State<ExpenseManagementPage> createState() => _ExpenseManagementPageState();
}

class _ExpenseManagementPageState extends State<ExpenseManagementPage> {
  late final ExpenseManagementAccess _access =
      widget.access ?? ExpenseManagementRepository();
  List<Map<String, dynamic>> _companies = [];
  String? _company, _actor, _error;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  ExpenseReviewWorkspace? _data;
  ExpenseReviewCommand? _pending;
  bool _busy = true;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  bool _current(int g) =>
      mounted && g == _generation && _access.actor == _actor;
  Future<void> _start() async {
    final g = ++_generation;
    setState(() {
      _busy = true;
      _data = null;
      _error = null;
    });
    try {
      _actor = _access.actor;
      if (_actor == null) throw StateError('ログインが必要です。');
      final companies = await _access.companies();
      if (!_current(g)) return;
      _companies = companies;
      if (!_companies.any((c) => c['company_id'] == _company)) {
        _company = companies.length == 1
            ? companies.single['company_id']
            : null;
      }
      if (_company != null) await _read(g);
    } catch (_) {
      if (mounted && g == _generation) _error = '経費一覧を取得できません。再読み込みしてください。';
    } finally {
      if (mounted && g == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _read(int g) async {
    final pending = await _access.pending(_company!);
    if (!_current(g)) return;
    _pending = pending;
    final data = await _access.load(_company!, _month);
    if (!_current(g)) return;
    _data = data;
  }

  Future<void> _reload() async {
    if (_busy || _company == null) return;
    final g = ++_generation;
    setState(() {
      _busy = true;
      _data = null;
      _error = null;
    });
    try {
      await _read(g);
    } catch (_) {
      if (mounted && g == _generation) _error = '経費一覧を取得できません。再読み込みしてください。';
    } finally {
      if (mounted && g == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _act(
    ExpenseClaim claim,
    String action, [
    ExpenseAllocation? destination,
  ]) async {
    if (_busy || _pending != null || _data == null || _access.actor != _actor) {
      return;
    }
    final command = ExpenseReviewCommand.create(
      _actor!,
      _company!,
      claim.id,
      _data!.revisions[claim.id]!,
      action,
      destination,
    );
    await _execute(command);
  }

  Future<void> _execute(ExpenseReviewCommand command) async {
    if (_busy || _access.actor != _actor) return;
    final g = ++_generation;
    setState(() {
      _busy = true;
      _pending = command;
      _error = null;
    });
    try {
      await _access.execute(command);
      if (_current(g)) _pending = null;
    } catch (_) {
      if (_current(g)) _error = '更新結果を確認してください。保留操作があれば同じ操作を再確認できます。';
    } finally {
      if (_current(g)) {
        _data = null;
        try {
          await _read(g);
        } catch (_) {
          if (_current(g)) _error = '最新の一覧を確認できません。再読み込みしてください。';
        }
      }
      if (mounted && g == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _settings() async {
    final data = _data;
    if (_busy || data == null || !data.canConfigure || _pending != null) return;
    final actor = _actor, company = _company;
    final selected = data.approvers.toSet();
    final result = await showDialog<List<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('経費の承認担当'),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('経費ページだけの担当です。1〜3名を選択してください。'),
                  for (final c in data.candidates)
                    CheckboxListTile(
                      title: Text(c['name']),
                      value: selected.contains(c['user_id']),
                      onChanged: (v) => setDialog(() {
                        if (v == true) {
                          selected.add(c['user_id']);
                        } else {
                          selected.remove(c['user_id']);
                        }
                      }),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: selected.isEmpty || selected.length > 3
                  ? null
                  : () => Navigator.pop(context, selected.toList()),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (!mounted ||
        result == null ||
        _access.actor != actor ||
        _company != company) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _access.configure(company!, result, data.settingsRevision);
    } catch (_) {
      if (mounted) _error = '担当設定の保存結果を再読み込みで確認してください。';
    }
    if (!mounted) return;
    final g = ++_generation;
    _data = null;
    try {
      await _read(g);
    } catch (_) {
      if (_current(g)) _error = '担当設定を取得できません。再読み込みしてください。';
    }
    if (mounted) setState(() => _busy = false);
  }

  Widget _header() => Column(
    children: [
      if (_companies.length > 1)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: DropdownButtonFormField<String>(
            initialValue: _company,
            decoration: const InputDecoration(labelText: '会社'),
            items: [
              for (final c in _companies)
                DropdownMenuItem(
                  value: c['company_id'] as String,
                  child: Text(c['company_name']),
                ),
            ],
            onChanged: _busy
                ? null
                : (v) {
                    setState(() {
                      _company = v;
                      _pending = null;
                      _data = null;
                    });
                    _reload();
                  },
          ),
        ),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            tooltip: '前月',
            onPressed: _busy
                ? null
                : () {
                    _month = DateTime(_month.year, _month.month - 1);
                    _reload();
                  },
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Text(
              '${_month.year}年${_month.month}月（利用月）',
              textAlign: TextAlign.center,
            ),
          ),
          IconButton(
            tooltip: '翌月',
            onPressed: _busy
                ? null
                : () {
                    _month = DateTime(_month.year, _month.month + 1);
                    _reload();
                  },
            icon: const Icon(Icons.chevron_right),
          ),
          IconButton(
            tooltip: '再読み込み',
            onPressed: _busy ? null : (_company == null ? _start : _reload),
            icon: const Icon(Icons.refresh),
          ),
          if (_data?.canConfigure == true)
            IconButton(
              tooltip: '経費の承認担当',
              onPressed: _busy || _pending != null ? null : _settings,
              icon: const Icon(Icons.manage_accounts),
            ),
        ],
      ),
      if (_pending != null)
        ListTile(
          title: const Text('結果確認待ちの操作があります'),
          subtitle: const Text('別の変更を行う前に、同じ操作の結果を確認してください。'),
          trailing: TextButton(
            onPressed: _busy ? null : () => _execute(_pending!),
            child: const Text('同じ操作を再確認'),
          ),
        ),
      if (_error != null)
        Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
      if (_busy) const LinearProgressIndicator(),
    ],
  );
  @override
  Widget build(BuildContext context) {
    if (_actor != null && _access.actor != _actor) {
      return Scaffold(
        appBar: AppBar(
          toolbarHeight: kToolbarHeight,
          title: const Text('経費申請一覧'),
        ),
        body: const Center(child: Text('ログイン情報が変わりました。画面を開き直してください。')),
      );
    }
    final data = _data;
    if (data == null) {
      return Scaffold(
        appBar: AppBar(
          toolbarHeight: kToolbarHeight,
          title: const Text('経費申請一覧'),
        ),
        body: Column(
          children: [
            _header(),
            if (!_busy && _error == null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _companies.isEmpty
                      ? '経費の管理者・承認担当として利用できる会社はありません。'
                      : '会社を選択してください。',
                ),
              ),
          ],
        ),
      );
    }
    final enabled = !_busy && _pending == null && data.canReview;
    return ExpenseClaimsPage(
      claims: data.claims,
      header: _header(),
      canDecide: (c) => data.canDecide(c, _actor!),
      onApprove: enabled ? (c) => _act(c, 'approve') : null,
      onReject: enabled ? (c) => _act(c, 'reject') : null,
      onAllocate: enabled ? (c, d) => _act(c, 'allocate', d) : null,
      destinations: data.destinations,
    );
  }
}
