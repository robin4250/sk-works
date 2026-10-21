import 'dart:async';
import 'package:flutter/material.dart';
import 'company_representative_repository.dart';

/// Explicit-company save, separate from the legacy whole contact form.
class CompanyRepresentativeCard extends StatefulWidget {
  const CompanyRepresentativeCard({super.key, this.repository});
  final CompanyRepresentativeRepository? repository;
  @override State<CompanyRepresentativeCard> createState() => _CardState();
}
class _CardState extends State<CompanyRepresentativeCard> with WidgetsBindingObserver {
  CompanyRepresentativeRepository? _repo;
  StreamSubscription<void>? _revocation;
  final _text = TextEditingController();
  List<({String id, String name})> _choices = [];
  CompanyRepresentativeSnapshot? _snapshot;
  String? _company, _error;
  bool _busy = true, _revoked = false, _saved = false, _mustReload = false;
  @override void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _repo = widget.repository ?? CompanyRepresentativeRepository.maybeCreate();
    _revocation = _repo?.invalidations.listen((_) => _clear());
    _loadChoices();
  }
  void _clear() {
    if (mounted && !_revoked) { setState(() {
      _revoked = true; _snapshot = null; _choices = []; _company = null;
      _text.clear(); _saved = false; _busy = false;
      _error = '会社データを開き直してください。';
    }); }
  }
  @override void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && !_revoked) {
      _repo?.revoke();
      if (mounted) { setState(() {
        _revoked = true; _snapshot = null; _choices = []; _text.clear();
        _error = '会社データを開き直してください。';
      }); }
    }
  }
  Future<void> _loadChoices() async {
    try {
      if (_repo == null) { throw StateError('unavailable'); }
      final choices = await _repo!.choices();
      if (!mounted || _revoked) { return; }
      setState(() { _choices = choices; _busy = false; });
    } catch (_) {
      if (mounted && !_revoked) { setState(() {
        _busy = false; _error = '代表者の設定を利用できません。時間をおいて開き直してください。';
      }); }
    }
  }
  Future<void> _select(String? id) async {
    if (id == null || _repo == null || _busy) { return; }
    setState(() { _company = id; _busy = true; _snapshot = null; _text.clear(); _saved = false; _error = null; });
    try {
      final value = await _repo!.selectCompany(id);
      if (!mounted || _revoked || _company != id) { return; }
      setState(() { _snapshot = value; _text.text = value.representative; _mustReload = false; });
    } catch (_) {
      if (mounted && !_revoked) { setState(() => _error = '選択した会社の代表者設定を取得できません。'); }
    } finally { if (mounted) { setState(() => _busy = false); } }
  }
  Future<void> _reload() async {
    if (_repo == null || _busy) { return; }
    setState(() { _busy = true; _saved = false; });
    try {
      final value = await _repo!.reload();
      if (!mounted || _revoked || value.companyId != _company) { return; }
      setState(() { _snapshot = value; _text.text = value.representative; _mustReload = false; _error = null; });
    } catch (_) {
      if (mounted && !_revoked) { setState(() => _error = '設定を再確認できません。会社データを開き直してください。'); }
    } finally { if (mounted) { setState(() => _busy = false); } }
  }
  Future<void> _save() async {
    final snapshot = _snapshot;
    if (_repo == null || snapshot == null || _busy || _mustReload) { return; }
    setState(() { _busy = true; _saved = false; _error = null; });
    try {
      final value = await _repo!.save(snapshot, _text.text);
      if (!mounted || _revoked || value.companyId != _company) { return; }
      setState(() { _snapshot = value; _text.text = value.representative; _saved = true; });
    } catch (_) {
      if (mounted && !_revoked) { setState(() {
        _mustReload = true; _error = '保存結果を確認できません。入力内容を控え、設定を再読込して確認してください。';
      }); }
    } finally { if (mounted) { setState(() => _busy = false); } }
  }
  @override void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _revocation?.cancel(); _repo?.dispose(); _text.dispose(); super.dispose();
  }
  @override Widget build(BuildContext context) => Card(
    child: Padding(padding: const EdgeInsets.all(16), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('注文書の発注者代表者名', style: Theme.of(context).textTheme.titleMedium)),
          IconButton(tooltip: '代表者名のヘルプ', icon: const Icon(Icons.help_outline), onPressed: () => showDialog<void>(
            context: context, builder: (context) => AlertDialog(
              title: const Text('発注者の代表者名'),
              content: const Text('登録する会社を選び、代表者名だけを保存します。会社名・住所・電話などの保存とは別です。\n新規注文書の発注者代表者名に使用します。保存済み注文書や手入力した帳票は変更しません。\n結果を確認できない場合は再保存せず、設定を再読込してください。'),
              actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('閉じる'))],
            ),
          )),
        ]),
        if (_busy) const LinearProgressIndicator(),
        if (!_revoked && _choices.isNotEmpty)
          DropdownButtonFormField<String>(
            initialValue: _company, decoration: const InputDecoration(labelText: '代表者を登録する会社'),
            items: [for (final choice in _choices) DropdownMenuItem(value: choice.id, child: Text(choice.name))],
            onChanged: _busy ? null : _select,
          ),
        if (_snapshot != null && !_revoked) ...[
          const SizedBox(height: 8), Text('保存先：${_snapshot!.name}'),
          TextField(controller: _text, enabled: !_busy && !_mustReload,
            decoration: const InputDecoration(labelText: '代表者名（80文字以内）')),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            FilledButton(onPressed: _busy || _mustReload ? null : _save, child: const Text('代表者名を保存')),
            TextButton(onPressed: _busy ? null : _reload, child: const Text('設定を再読込')),
          ]),
        ],
        if (_company != null && _snapshot == null && !_revoked)
          TextButton(onPressed: _busy ? null : _reload, child: const Text('設定を再読込')),
        if (_saved) const Text('選択した会社の代表者名を保存しました。'),
        if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        if (!_busy && _error == null && _choices.isEmpty) const Text('代表者を設定できる会社がありません。'),
      ],
    )),
  );
}
