import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/supabase_backend.dart';
import 'master_credential_repository.dart';
import 'master_credential_setup_page.dart';
import 'master_password_entry_repository.dart';

/// Disconnected unless the explicit compile-time candidate switch is enabled.
/// A verified reply grants only this local entry; it is not an operation proof.
class MasterPasswordProtectedPage extends StatefulWidget {
  const MasterPasswordProtectedPage({super.key, required this.title, required this.child, this.access, this.settingsBuilder});
  final String title;
  final Widget child;
  final MasterPasswordEntryAccess? access;
  final Widget Function(MasterCredentialAccess access)? settingsBuilder;
  @override State<MasterPasswordProtectedPage> createState() => _MasterPasswordProtectedPageState();
}
class _MasterPasswordProtectedPageState extends State<MasterPasswordProtectedPage> with WidgetsBindingObserver {
  MasterPasswordEntryAccess? _access;
  MasterCredentialBinding? _loaded;
  MasterCredentialStatus? _status;
  StreamSubscription<void>? _subscription;
  final _password = TextEditingController();
  Timer? _expiry;
  Completer<bool>? _resume;
  VoidCallback? _clearCaptured;
  bool _busy = false, _loading = true, _nativePrompt = false, _unlocked = false;
  String? _message;
  int _generation = 0;
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;
  bool get _current => ModalRoute.of(context)?.isCurrent == true;
  bool _valid(int generation, MasterCredentialBinding binding, {bool nativeInactive = false}) => mounted && generation == _generation && binding.sameAs(_access?.binding) && _current && (_lifecycle == AppLifecycleState.resumed || nativeInactive && _nativePrompt && _lifecycle == AppLifecycleState.inactive);
  @override void initState() {
    super.initState();
    _lifecycle = WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _load(); });
  }
  @override void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_current && !_unlocked && (_loaded != null || _busy)) _lock(rebuild: false);
  }
  void _lock({bool rebuild = true}) {
    if (!mounted) return;
    _generation++; _password.clear(); _clearCaptured?.call();
    _expiry?.cancel(); _expiry = null;
    final wait = _resume; _resume = null;
    if (wait != null && !wait.isCompleted) wait.complete(false);
    _nativePrompt = false; _unlocked = false; _busy = false; _loading = false;
    _status = null; _loaded = null;
    _message = 'Master本人確認を中断しました。再読み込みしてください。';
    if (rebuild && mounted) setState(() {});
  }
  @override void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    if (state == AppLifecycleState.resumed) {
      final wait = _resume;
      if (wait != null && !wait.isCompleted) wait.complete(true);
    } else if (state == AppLifecycleState.inactive && _nativePrompt) {
      _password.clear();
    } else { _lock(); }
  }
  Future<MasterPasswordEntryAccess?> _defaultAccess() async {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    final actor = client.auth.currentUser?.id;
    if (actor == null) return null;
    final prefs = await SharedPreferences.getInstance();
    if (client.auth.currentUser?.id != actor) return null;
    final key = prefs.getString('sko_master_device_key_$actor');
    if (key == null || key.length < 32 || key.length > 256) return null;
    return MasterPasswordEntryRepository(client, deviceKey: key);
  }
  Future<void> _load() async {
    if (_busy || _lifecycle != AppLifecycleState.resumed || !_current) return;
    final generation = ++_generation;
    setState(() { _loading = true; _message = null; _status = null; _unlocked = false; });
    try {
      final access = _access ?? widget.access ?? await _defaultAccess();
      if (!mounted || generation != _generation) return;
      if (access == null || access.binding == null) throw const MasterCredentialRejected('denied');
      if (_access == null) {
        _access = access;
        _subscription = access.changes.listen((_) { if (_loaded != null && !_loaded!.sameAs(access.binding)) _lock(); }, onError: (Object _) => _lock());
      }
      final binding = access.binding!;
      _loaded = binding;
      final status = await access.read(binding);
      if (!_valid(generation, binding)) return;
      setState(() => _status = status);
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _message = 'Master本人・信頼済み端末・専用認証の準備を確認できません。未登録端末は正規の端末登録・復旧を先に行ってください。');
    } finally { if (mounted && generation == _generation) setState(() => _loading = false); }
  }
  Future<bool> _face(int generation, MasterCredentialBinding binding) async {
    final access = _access!;
    if (!await access.biometricAvailable() || !_valid(generation, binding)) return false;
    _nativePrompt = true;
    final ok = await access.biometric();
    if (!ok || !_valid(generation, binding, nativeInactive: true)) return false;
    if (_lifecycle == AppLifecycleState.inactive) {
      final wait = Completer<bool>(); _resume = wait;
      final resumed = await wait.future;
      if (identical(_resume, wait)) _resume = null;
      if (!resumed || !_valid(generation, binding)) return false;
    }
    _nativePrompt = false;
    return _valid(generation, binding);
  }
  Future<void> _unlock() async {
    final access = _access, binding = _loaded, status = _status;
    if (_busy || _loading || access == null || binding == null || status == null || !status.configured || !_valid(_generation, binding)) return;
    String password = _password.text;
    _password.clear();
    if (password.isEmpty || utf8.encode(password).length > 72) { setState(() => _message = 'Master専用パスワードを入力してください。'); return; }
    final clearCaptured = () { password = ''; };
    _clearCaptured = clearCaptured;
    final generation = ++_generation;
    setState(() { _busy = true; _message = null; });
    try {
      final current = await access.read(binding);
      if (!_valid(generation, binding)) return;
      if (!current.configured || current.version != status.version) throw const MasterCredentialRejected('conflict');
      final request = newMasterCredentialRequestId();
      final challenge = await access.beginUnlock(binding, current.version, request);
      if (!_valid(generation, binding)) return;
      if (!await _face(generation, binding)) throw const MasterCredentialRejected('not_verified');
      if (!_valid(generation, binding)) return;
      await access.verifyUnlock(binding, current.version, request, challenge, password);
      password = '';
      if (!_valid(generation, binding)) return;
      final after = await access.read(binding);
      if (!_valid(generation, binding) || !after.configured || after.version != current.version) throw const MasterCredentialRejected('conflict');
      _expiry?.cancel(); _expiry = Timer(const Duration(minutes: 15), _lock);
      setState(() => _unlocked = true);
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _message = 'Master専用の本人確認を完了できませんでした。第2パスワードの代用はできません。再読み込みして確認してください。');
    } finally {
      password = '';
      if (identical(_clearCaptured, clearCaptured)) _clearCaptured = null;
      if (mounted && generation == _generation) setState(() { _busy = false; _nativePrompt = false; });
    }
  }
  Future<void> _settings() async {
    final access = _access, binding = _loaded;
    if (_busy || _loading || access == null || binding == null || !_valid(_generation, binding)) return;
    final generation = ++_generation;
    setState(() { _busy = true; _message = null; });
    try {
      await access.read(binding);
      if (!_valid(generation, binding)) return;
      if (!await _face(generation, binding)) throw const MasterCredentialRejected('not_verified');
      if (!_valid(generation, binding)) return;
      if (!mounted) return;
      await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => widget.settingsBuilder?.call(access.settingsAccess) ?? MasterCredentialSetupPage(access: access.settingsAccess)));
      // Settings success never grants unlock. Re-read and request dedicated auth.
      if (mounted && binding.sameAs(access.binding) && _current && _lifecycle == AppLifecycleState.resumed) {
        _busy = false;
        await _load();
      }
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _message = 'Master専用設定を開けませんでした。本人確認からやり直してください。');
    } finally { if (mounted && generation == _generation) setState(() { _busy = false; _nativePrompt = false; }); }
  }
  @override void dispose() {
    _generation++; _clearCaptured?.call(); _password.clear(); _expiry?.cancel();
    final wait = _resume; if (wait != null && !wait.isCompleted) wait.complete(false);
    _subscription?.cancel(); WidgetsBinding.instance.removeObserver(this); _password.dispose(); super.dispose();
  }
  @override Widget build(BuildContext context) {
    if (_unlocked) return widget.child;
    final status = _status;
    return Scaffold(appBar: AppBar(title: Text(widget.title)), body: SafeArea(child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('Master専用本人確認', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      const Text('Master本人の信頼済み端末でのみ使用できます。通常ログイン・第2パスワードとは別の専用パスワードです。'),
      if (_message != null) Text(_message!),
      if (_loading) const Center(child: CircularProgressIndicator()),
      if (status != null && !status.configured) ...[
        const Text('Master専用パスワードが未設定です。最初の登録を行ってください。'),
        FilledButton(onPressed: _busy ? null : _settings, child: const Text('Master専用パスワードを初回設定')),
      ],
      if (status != null && status.configured) ...[
        TextField(key: const Key('master-dedicated-password'), controller: _password, enabled: !_busy, obscureText: true, autocorrect: false, enableSuggestions: false, decoration: const InputDecoration(labelText: 'Master専用パスワード')),
        FilledButton(onPressed: _busy ? null : _unlock, child: const Text('Face ID / Touch ID＋Master専用パスワードで開く')),
        TextButton(onPressed: _busy ? null : _settings, child: const Text('Master専用パスワードを変更')),
      ],
      if (_busy) const Center(child: CircularProgressIndicator()),
      if (!_busy && !_loading) OutlinedButton(onPressed: _load, child: const Text('再読み込み')),
    ])))));
  }
}
