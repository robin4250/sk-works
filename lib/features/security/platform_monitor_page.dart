import 'package:flutter/material.dart';

import 'platform_monitor_repository.dart';

class PlatformMonitorPage extends StatefulWidget {
  const PlatformMonitorPage({super.key, this.checkAvailable, this.loadSnapshot});
  final Future<bool> Function()? checkAvailable;
  final Future<PlatformMonitorSnapshot> Function(String password)? loadSnapshot;
  @override
  State<PlatformMonitorPage> createState() => _PlatformMonitorPageState();
}

class _PlatformMonitorPageState extends State<PlatformMonitorPage>
    with WidgetsBindingObserver {
  final _password = TextEditingController();
  final _repository = PlatformMonitorRepository.maybeCreate();
  bool _checking = true;
  bool _available = false;
  bool _busy = false;
  String? _error;
  PlatformMonitorSnapshot? _snapshot;
  int _generation = 0;
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;

  @override
  void initState() {
    super.initState();
    _lifecycle = WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    if (_lifecycle == AppLifecycleState.resumed) {
      _check();
    } else {
      _checking = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasResumed = _lifecycle == AppLifecycleState.resumed;
    _lifecycle = state;
    if (state != AppLifecycleState.resumed) {
      // Every background transition invalidates both capability and read work.
      // Returning later never restores a snapshot or reuses its proof/password.
      _generation++;
      _password.clear();
      setState(() {
        _checking = false;
        _available = false;
        _busy = false;
        _snapshot = null;
        _error = null;
      });
    } else if (!wasResumed) {
      setState(() { _checking = true; });
      _check();
    }
  }

  Future<void> _check() async {
    if (_lifecycle != AppLifecycleState.resumed) return;
    final generation = ++_generation;
    try {
      final check = widget.checkAvailable ?? _repository?.available;
      final available = check != null && await check();
      if (mounted && generation == _generation && _lifecycle == AppLifecycleState.resumed) {
        setState(() { _checking = false; _available = available; });
      }
    } catch (_) {
      if (mounted && generation == _generation && _lifecycle == AppLifecycleState.resumed) {
        setState(() { _checking = false; _error = '接続・権限を確認できません。再度開いてください。'; });
      }
    }
  }

  Future<void> _load() async {
    if (_busy || !_available || _lifecycle != AppLifecycleState.resumed || _password.text.isEmpty) return;
    final load = widget.loadSnapshot ?? _repository?.load;
    if (load == null) return;
    final generation = ++_generation;
    final password = _password.text;
    _password.clear();
    setState(() { _busy = true; _error = null; _snapshot = null; });
    bool current() => mounted && generation == _generation && _lifecycle == AppLifecycleState.resumed;
    try {
      final snapshot = await load(password);
      if (current()) setState(() => _snapshot = snapshot);
    } on PlatformMonitorUnavailable {
      if (current()) setState(() => _available = false);
    } catch (_) {
      if (current()) setState(() => _error = '監視記録を取得できません。認証・権限・接続を確認してください。');
    } finally {
      if (current()) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _generation++;
    _password.clear();
    _password.dispose();
    super.dispose();
  }

  static const _results = {
    'unknown': '結果不明', 'http_success': 'HTTP成功（攻撃判定ではありません）',
    'unauthenticated': '認証要求を拒否（401）', 'forbidden': 'アクセスを拒否（403）',
    'rate_limited': '回数制限（429）', 'server_error': 'サーバーエラー',
    'permission_denied': '権限エラー（42501・原因未確定）',
  };

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('プラットフォーム監視')),
      body: _checking ? const Center(child: CircularProgressIndicator()) : ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Supabaseの実ログ由来の安全化済み記録です。合成のセキュリティ記録とは別に表示します。日時・対象は収集範囲内のみで、攻撃や人物の特定を意味しません。'),
          const SizedBox(height: 12),
          if (_error != null) Text(_error!),
          if (!_available && _error == null)
            const Text('監視未開始：収集または再認証の準備が完了していません。安全確認済み・記録なしという意味ではありません。'),
          if (_available) ...[
            TextField(controller: _password, enabled: !_busy, obscureText: true, autocorrect: false, enableSuggestions: false, decoration: const InputDecoration(labelText: 'ログインパスワード（表示のたびに再認証）')),
            FilledButton(onPressed: _busy ? null : _load, child: Text(_busy ? '認証・取得中…' : '再認証して記録を表示')),
          ],
          if (_snapshot case final snapshot?) ...[
            const Text('常時監視の証明ではありません。各最新100件・保存対象7日以内。収集が止まった時間や保存上限の欠落は、下の収集範囲と合わせて確認してください。'),
            if (snapshot.windows.isEmpty)
              const Text('収集範囲の保存記録がありません。監視が動作した証拠はまだありません。'),
            for (final window in snapshot.windows)
              ListTile(title: Text('${window['source']}・${window['event_count']}件'), subtitle: Text('${window['window_from']} ～ ${window['window_to']}\n${window['coverage'] == 'capacity_limited' ? '件数上限に到達・不足の可能性' : '指定範囲の取得（連続収集は未保証）'}')),
            if (snapshot.events.isEmpty)
              const Text('保存対象の記録はありません。攻撃がなかったことや安全性を証明しません。'),
            for (final event in snapshot.events)
              ListTile(title: Text(_results[event['result']]!), subtitle: Text('${event['occurred_at']}・${event['source']}\n対象：${event['target_key'] == null ? '不明' : (event['target_key'] as String).substring(0, 12)}（匿名化）\nアクセス元：不明・同一元の追跡はできません。')),
          ],
        ],
      ),
    ),
  );
}
