import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'master_credential_repository.dart';

/// Unconnected candidate. This page never grants entry to a Master screen.
class MasterCredentialSetupPage extends StatefulWidget {
  const MasterCredentialSetupPage({super.key, required this.access});
  final MasterCredentialAccess access;
  @override State<MasterCredentialSetupPage> createState() => _MasterCredentialSetupPageState();
}
class _MasterCredentialSetupPageState extends State<MasterCredentialSetupPage> with WidgetsBindingObserver {
  final _existing = TextEditingController(), _password = TextEditingController(), _confirm = TextEditingController();
  StreamSubscription<void>? _subscription;
  MasterCredentialStatus? _status;
  MasterCredentialBinding? _loaded;
  MasterCredentialPending? _pending;
  MasterCredentialChallenge? _challenge;
  VoidCallback? _clearCaptured;
  bool _busy = false, _complete = false;
  String? _message;
  int _generation = 0;
  bool get _foreground => WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  bool get _current => ModalRoute.of(context)?.isCurrent == true;
  @override void initState() {
    super.initState(); WidgetsBinding.instance.addObserver(this);
    _subscription = widget.access.changes.listen((_) { if (_loaded != null && !_loaded!.sameAs(widget.access.binding)) _invalidate(); }, onError: (Object _) => _invalidate());
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _load(); });
  }
  @override void didChangeDependencies() {
    super.didChangeDependencies();
    if (ModalRoute.of(context)?.isCurrent == false && (_status != null || _busy)) _invalidate(rebuild: false);
  }
  void _clear() { _existing.clear(); _password.clear(); _confirm.clear(); _challenge = null; _clearCaptured?.call(); }
  void _invalidate({bool rebuild = true}) {
    _generation++; _clear(); _complete = false; _status = null; _loaded = null; _busy = false;
    _message = '本人確認を中断しました。再読み込みしてください。';
    if (rebuild && mounted) setState(() {});
  }
  @override void didChangeAppLifecycleState(AppLifecycleState state) { if (state != AppLifecycleState.resumed) _invalidate(); }
  bool _valid(int generation, MasterCredentialBinding binding) => mounted && generation == _generation && _foreground && _current && binding.sameAs(widget.access.binding);
  Future<void> _load() async {
    if (_busy || !_foreground || !_current) return;
    final binding = widget.access.binding;
    if (binding == null) { setState(() { _status = null; _message = 'Master本人確認を利用できません。'; }); return; }
    final generation = ++_generation;
    _loaded = binding;
    setState(() { _busy = true; _status = null; _message = null; });
    try {
      final status = await widget.access.read(binding);
      if (!_valid(generation, binding)) return;
      final persisted = await widget.access.pending(binding);
      if (!_valid(generation, binding)) return;
      final pending = _pending;
      setState(() { _status = status; _pending = pending != null && pending.belongsTo(binding) ? pending : persisted; });
    } catch (_) {
      if (_valid(generation, binding)) setState(() { _status = null; _message = 'Master本人確認を利用できません。時間をおいて再読み込みしてください。'; });
    } finally { if (mounted && generation == _generation) setState(() => _busy = false); }
  }
  Future<bool> _forget(MasterCredentialPending pending) async {
    try { await widget.access.forget(pending); return true; } catch (_) { return false; }
  }
  Future<void> _save() async {
    final status = _status, binding = _loaded;
    if (_busy || status == null || binding == null || _pending != null || !_valid(_generation, binding)) return;
    if (_existing.text.isEmpty || utf8.encode(_existing.text).length > 72 || _password.text.length < 8 || utf8.encode(_password.text).length > 72 || _password.text != _confirm.text) {
      setState(() => _message = '確認用パスワードと、一致する新しいMaster専用パスワードを入力してください。新しいパスワードは8文字以上、UTF-8で72バイト以内です。'); return;
    }
    String existing = _existing.text, password = _password.text;
    _clearCaptured = () { existing = ''; password = ''; };
    _existing.clear(); _password.clear(); _confirm.clear();
    final generation = ++_generation;
    final pending = MasterCredentialPending(actor: binding.actor, sessionId: binding.sessionId, deviceFingerprint: binding.deviceFingerprint, requestId: newMasterCredentialRequestId(), operation: status.configured ? 'change' : 'setup', version: status.version);
    bool submitted = false;
    setState(() { _busy = true; _message = null; });
    try {
      final challenge = await widget.access.begin(binding, pending);
      if (!_valid(generation, binding)) return;
      _challenge = challenge;
      _pending = pending;
      await widget.access.remember(pending);
      if (!_valid(generation, binding)) return;
      if (!_challenge!.expiresAt.isAfter(DateTime.now())) throw const MasterCredentialRejected('expired');
      submitted = true;
      await widget.access.commit(binding, pending, _challenge!, verificationPassword: existing, newPassword: password);
      if (!await _forget(pending)) throw StateError('Operation identity unresolved');
      if (!_valid(generation, binding)) return;
      setState(() { _pending = null; _complete = true; _status = null; _message = null; });
    } on MasterCredentialRejected {
      final cleared = await _forget(pending);
      if (_valid(generation, binding)) setState(() { if (cleared) _pending = null; _message = '本人確認を完了できませんでした。入力内容・権限を確認して再読み込みしてください。'; _status = null; });
    } catch (_) {
      if (_valid(generation, binding)) setState(() { _status = null; _message = submitted ? '保存結果を確認できません。再送せず、結果を照合してください。' : '準備を完了できませんでした。再読み込みしてください。'; });
    } finally {
      existing = ''; password = ''; _clearCaptured = null; _challenge = null;
      if (!submitted) {
        final cleared = await _forget(pending);
        if (cleared && _pending?.requestId == pending.requestId) _pending = null;
      }
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }
  Future<void> _reconcile() async {
    final binding = widget.access.binding, pending = _pending;
    if (_busy || binding == null || pending == null || !pending.belongsTo(binding) || !_foreground || !_current) return;
    final generation = ++_generation; _loaded = binding;
    setState(() { _busy = true; _message = null; });
    try {
      final found = await widget.access.receipt(binding, pending);
      if (!_valid(generation, binding)) return;
      if (found) {
        if (!await _forget(pending)) throw StateError('Operation identity unresolved');
        if (!_valid(generation, binding)) return;
        setState(() { _pending = null; _complete = true; });
      } else { setState(() => _message = '保存結果はまだ確定できません。再送せず、時間をおいて再度照合してください。'); }
    } catch (_) { if (_valid(generation, binding)) setState(() => _message = '結果を照合できませんでした。再送せず、時間をおいて確認してください。'); }
    finally { if (mounted && generation == _generation) setState(() => _busy = false); }
  }
  @override void dispose() {
    _generation++; _clear(); _subscription?.cancel(); WidgetsBinding.instance.removeObserver(this);
    _existing.dispose(); _password.dispose(); _confirm.dispose(); super.dispose();
  }
  @override Widget build(BuildContext context) {
    final status = _status;
    return Scaffold(appBar: AppBar(title: const Text('Master専用パスワード')), body: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_complete) ...[
        const Icon(Icons.check_circle_outline, size: 56),
        const Text('Master専用パスワードの保存が完了しました。'),
        const Text('通常ログイン・会社情報・第2パスワードは変更していません。'),
        FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('完了して戻る')),
      ] else ...[
        const Text('Master本人だけが登録・変更できます。通常ログイン用・第2パスワードとは別のパスワードです。'),
        if (_message != null) Text(_message!),
        if (_pending != null) ...[
          const Text('確認待ちの保存があります。新しい保存は送信できません。'),
          FilledButton(onPressed: _busy ? null : _reconcile, child: const Text('保存結果を照合')),
        ] else if (status != null) ...[
          Text(status.configured ? 'Master専用パスワードを変更' : 'Master専用パスワードを初回登録'),
          TextField(controller: _existing, enabled: !_busy, obscureText: true, enableSuggestions: false, autocorrect: false, decoration: InputDecoration(labelText: status.configured ? '現在のMaster専用パスワード' : '現在の第2パスワード（初回本人確認）')),
          TextField(controller: _password, enabled: !_busy, obscureText: true, enableSuggestions: false, autocorrect: false, decoration: const InputDecoration(labelText: '新しいMaster専用パスワード')),
          TextField(controller: _confirm, enabled: !_busy, obscureText: true, enableSuggestions: false, autocorrect: false, decoration: const InputDecoration(labelText: '新しいMaster専用パスワード（確認）')),
          FilledButton(onPressed: _busy ? null : _save, child: Text(status.configured ? '変更して保存' : '初回登録して保存')),
        ],
        if (_busy) const Center(child: CircularProgressIndicator()),
        if (!_busy && status == null && _pending == null) OutlinedButton(onPressed: _load, child: const Text('再読み込み')),
      ],
    ]))));
  }
}
