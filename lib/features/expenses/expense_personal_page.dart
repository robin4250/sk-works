import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'expense_claim.dart';
import 'expense_claims_page.dart';
import 'expense_submission_repository.dart';

class ExpensePersonalPage extends StatefulWidget {
  const ExpensePersonalPage({super.key, this.access});
  final ExpenseSubmissionAccess? access;
  @override
  State<ExpensePersonalPage> createState() => _ExpensePersonalPageState();
}

class _ExpensePersonalPageState extends State<ExpensePersonalPage> {
  ExpenseSubmissionAccess? _access;
  final _description = TextEditingController(),
      _amount = TextEditingController();
  List<Map<String, dynamic>> _scopes = [];
  Map<String, dynamic>? _scope;
  List<ExpenseClaim> _history = [];
  ExpenseSubmission? _pending;
  DateTime _date = DateTime.now(), _month = DateTime.now();
  bool _busy = true, _ready = false;
  String? _error, _actor;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    try {
      _access = widget.access ?? ExpenseSubmissionRepository();
    } catch (_) {
      _error = '経費申請に接続できません。';
      _busy = false;
    }
    if (_access != null) _loadScopes();
  }

  @override
  void dispose() {
    _generation++;
    _description.dispose();
    _amount.dispose();
    super.dispose();
  }

  bool _current(int generation) =>
      mounted && generation == _generation && _access?.actor == _actor;
  Future<void> _loadScopes() async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _ready = false;
      _error = null;
    });
    try {
      _actor = _access!.actor;
      if (_actor == null) throw StateError('ログインが必要です。');
      final scopes = await _access!.scopes();
      if (!_current(generation)) return;
      setState(() {
        _scopes = scopes;
        _scope = scopes.length == 1 ? scopes.single : null;
      });
      if (_scope != null) await _loadSelection(generation);
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = '申請先を確認できません。再読み込みしてください。');
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _loadSelection(int generation) async {
    final scope = _scope!;
    final pending = await _access!.pending(
      scope['company_id'],
      scope['worker_id'],
    );
    if (!_current(generation)) return;
    setState(() {
      _pending = pending;
      _ready = true;
    });
    final history = await _access!.history(
      scope['company_id'],
      scope['worker_id'],
      _month,
    );
    if (!_current(generation)) return;
    setState(() => _history = history);
  }

  Future<void> _reload() async {
    if (_scope == null) return _loadScopes();
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _ready = false;
      _error = null;
      _history = [];
    });
    try {
      await _loadSelection(generation);
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = '申請履歴を確認できません。再読み込みしてください。');
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _send() async {
    if (_busy || !_ready || _scope == null || _access?.actor != _actor) return;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final draft =
          _pending ??
          ExpenseSubmission.create(
            _actor!,
            _scope!['company_id'],
            _scope!['worker_id'],
            _date,
            _description.text,
            _amount.text,
          );
      setState(() => _pending = draft);
      await _access!.submit(draft);
      if (!_current(generation)) return;
      setState(() {
        _pending = null;
        _description.clear();
        _amount.clear();
        _month = DateTime.parse(draft.date);
      });
      await _loadSelection(generation);
      if (mounted && _current(generation)) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('経費を申請しました')));
      }
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(
          () =>
              _error = _pending == null ? '$e' : '保存結果を確認できません。同じ申請を再確認してください。',
        );
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _pickDate({bool month = false}) async {
    final date = await showDatePicker(
      context: context,
      initialDate: month ? _month : _date,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (date == null || !mounted) return;
    if (month) {
      setState(() => _month = date);
      await _reload();
    } else {
      setState(() => _date = date);
    }
  }

  String _label(DateTime d) => '${d.year}/${d.month}/${d.day}';
  @override
  Widget build(BuildContext context) {
    final pending = _pending;
    final editable =
        !_busy && _ready && pending == null && _access?.actor == _actor;
    return Scaffold(
      appBar: AppBar(toolbarHeight: kToolbarHeight, title: const Text('経費申請')),
      body: _actor != null && _access?.actor != _actor
          ? const Center(child: Text('ログイン情報が変わりました。開き直してください。'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_busy) const LinearProgressIndicator(),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(_error!),
                  ),
                if (_scopes.length > 1)
                  DropdownButtonFormField<String>(
                    initialValue: _scope == null
                        ? null
                        : '${_scope!['company_id']}/${_scope!['worker_id']}',
                    decoration: const InputDecoration(labelText: '申請する本人の所属'),
                    items: [
                      for (final s in _scopes)
                        DropdownMenuItem(
                          value: '${s['company_id']}/${s['worker_id']}',
                          child: Text(
                            '${s['company_name']}・${s['worker_name']}',
                          ),
                        ),
                    ],
                    onChanged: _busy
                        ? null
                        : (value) {
                            setState(() {
                              _scope = _scopes.singleWhere(
                                (s) =>
                                    '${s['company_id']}/${s['worker_id']}' ==
                                    value,
                              );
                              _pending = null;
                              _description.clear();
                              _amount.clear();
                            });
                            _reload();
                          },
                  ),
                if (_scope != null) ...[
                  Text('${_scope!['company_name']}・${_scope!['worker_name']}'),
                  const SizedBox(height: 12),
                  if (pending != null)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          '確認中の申請\n${pending.date}　${pending.amount}円\n${pending.description}',
                        ),
                      ),
                    )
                  else ...[
                    OutlinedButton.icon(
                      onPressed: editable ? () => _pickDate() : null,
                      icon: const Icon(Icons.calendar_month),
                      label: Text('利用日　${_label(_date)}'),
                    ),
                    TextField(
                      controller: _description,
                      enabled: editable,
                      maxLength: 1000,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: '内容',
                        helperText: '税理士・会計士に申請する文章なので、分かりやすく詳細を書き込んでください',
                        helperMaxLines: 4,
                      ),
                    ),
                    TextField(
                      controller: _amount,
                      enabled: editable,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(labelText: '金額（円）'),
                    ),
                  ],
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: !_busy && _ready && _access?.actor == _actor
                        ? _send
                        : null,
                    child: Text(pending == null ? '申請する' : '同じ申請を再確認'),
                  ),
                  const Divider(height: 32),
                  OutlinedButton(
                    onPressed: _busy ? null : () => _pickDate(month: true),
                    child: Text('利用月　${_month.year}年${_month.month}月'),
                  ),
                  for (final claim in _history)
                    ListTile(
                      title: Text(claim.description),
                      subtitle: Text(
                        '${_label(claim.incurredOn)}　${expenseApprovalLabel(claim.approval)}',
                      ),
                      trailing: Text('${claim.amountYen}円'),
                    ),
                  if (_history.isNotEmpty)
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ExpenseClaimsPage(
                            claims: ExpenseClaims(
                              companyId: _scope!['company_id'],
                              claims: _history,
                            ),
                            applicantId: _scope!['worker_id'],
                          ),
                        ),
                      ),
                      child: const Text('個人の経費一覧を開く'),
                    ),
                ] else if (!_busy && _error == null)
                  const Text('申請できる本人の従業員登録がありません。'),
                TextButton(
                  onPressed: _busy ? null : _reload,
                  child: const Text('再読み込み'),
                ),
              ],
            ),
    );
  }
}
