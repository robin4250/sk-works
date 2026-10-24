import 'dart:async';

import 'package:flutter/material.dart';

import 'security_collector_repository.dart';

/// Read-only UI; collection, keys and both server gates are never activated here.
class SecurityCollectorPage extends StatefulWidget {
  const SecurityCollectorPage({super.key, this.repository});
  final SecurityCollectorRepository? repository;
  @override
  State<SecurityCollectorPage> createState() => _SecurityCollectorPageState();
}

class _SecurityCollectorPageState extends State<SecurityCollectorPage> with WidgetsBindingObserver {
  final _password = TextEditingController();
  late final SecurityCollectorRepository? _repository;
  StreamSubscription<void>? _subscription;
  String? _initialSession;
  SecurityCollectorSnapshot? _snapshot;
  bool _checking = true, _available = false, _busy = false, _revoked = false;
  String? _error;
  int _generation = 0;
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? SecurityCollectorRepository.maybeCreate();
    _initialSession = _repository?.sessionKey();
    _lifecycle = WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _subscription = _repository?.sessionChanges.listen((_) {
      if (_repository?.sessionKey() != _initialSession) _revoke();
    }, onError: (Object _) => _revoke());
    if (_lifecycle == AppLifecycleState.resumed) { _check(); }
    else { _checking = false; }
  }

  void _clear() {
    _generation++; _password.clear();
    _snapshot = null; _available = false; _busy = false; _checking = false;
  }

  void _revoke() {
    if (!mounted) return;
    setState(() { _clear(); _revoked = true; _error = '本人確認が失効しました。画面を閉じて開き直してください。'; });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    if (state != AppLifecycleState.resumed) {
      setState(() { _clear(); _error = null; });
    } else if (!_revoked) { _check(); }
  }

  bool _current(int generation) => mounted && generation == _generation &&
      !_revoked && _lifecycle == AppLifecycleState.resumed;

  Future<void> _check() async {
    if (_revoked || _lifecycle != AppLifecycleState.resumed) return;
    final generation = ++_generation;
    setState(() { _checking = true; _available = false; _snapshot = null; _error = null; });
    try {
      final available = await _repository?.available() ?? false;
      if (_current(generation)) setState(() { _available = available; });
    } catch (_) {
      if (_current(generation)) setState(() => _error = '接続・権限を確認できません。表示できない状態です。');
    } finally {
      if (_current(generation)) setState(() => _checking = false);
    }
  }

  Future<void> _load() async {
    if (_busy || !_available || _password.text.isEmpty || _revoked) return;
    final repository = _repository;
    if (repository == null) return;
    final generation = ++_generation;
    final password = _password.text; _password.clear();
    setState(() { _busy = true; _error = null; _snapshot = null; });
    try {
      final snapshot = await repository.load(password, isActive: () => _current(generation));
      if (_current(generation)) setState(() => _snapshot = snapshot);
    } on SecurityCollectorUnavailable {
      if (_current(generation)) setState(() { _available = false; _error = '収集記録の接続・再認証・提供状態が未準備か失効しています。安全確認済みや記録なしという意味ではありません。'; });
    } catch (_) {
      if (_current(generation)) setState(() => _error = '記録を取得できません。権限・認証・接続を確認してください。再表示には新しい再認証が必要です。');
    } finally {
      if (_current(generation)) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _generation++; _subscription?.cancel(); _password.clear(); _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('収集されたアクセス記録'), actions: [
      IconButton(icon: const Icon(Icons.help_outline), tooltip: 'ヘルプ', onPressed: () => showDialog<void>(
        context: context, builder: (context) => AlertDialog(title: const Text('収集記録について'),
          content: const Text('Master専用です。表示のたびに本人・セッション・この収集範囲に限定した再認証を行います。証明は一回だけ使い、端末へ保存しません。途中で取り消しても送信済みの読取は完了する場合がありますが、結果は表示しません。アプリが背景へ移ると表示を消します。収集・鍵・自動遮断を有効にする操作ではありません。'),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('閉じる'))])))
    ]),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('収集範囲内の観測記録です。不正アクセスや攻撃の確定、常時監視や安全性の証明ではありません。'),
      if (_checking) const LinearProgressIndicator(),
      if (_error != null) Text(_error!),
      if (!_checking && !_available && _error == null)
        const Text('未接続または提供準備中です。記録なし・安全確認済みという意味ではありません。'),
      if (_available && !_revoked) ...[
        TextField(key: const ValueKey('collector-password'), controller: _password,
          enabled: !_busy, obscureText: true, autocorrect: false, enableSuggestions: false,
          decoration: const InputDecoration(labelText: 'ログインパスワード（表示のたびに再認証）')),
        FilledButton(onPressed: _busy ? null : _load, child: const Text('再認証して収集記録を表示')),
      ],
      if (_busy) ...[
        const LinearProgressIndicator(),
        TextButton(onPressed: () { setState(() { _clear(); }); _check(); }, child: const Text('表示を取り消す')),
      ],
      if (_snapshot case final snapshot?) ...[
        const Text('最新100件・受信から7日以内の記録です。記録の欠落や収集の停止は、この表示だけでは判定できません。'),
        if (snapshot.events.isEmpty) const Text('対象範囲の保存記録はありません。攻撃がなかったことを示しません。'),
        for (final event in snapshot.events) ListTile(
          title: Text(event['event_kind'] == 'current_lure_touched' ? '現在の検知対象への接触を観測' : '以前の検知対象への接触を観測'),
          subtitle: Text('${event['occurred_at']}・世代 ${event['generation']}\n攻撃の確定ではありません。人物・接続元の特定はできません。')),
      ],
      if (!_busy && !_revoked) TextButton(onPressed: _check, child: const Text('接続状態を確認')),
    ]),
  );
}
