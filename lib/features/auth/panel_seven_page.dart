import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'panel_seven_repository.dart';

class PanelSevenPage extends StatefulWidget {
  const PanelSevenPage({super.key, required this.repository});
  final PanelSevenRepository repository;

  @override
  State<PanelSevenPage> createState() => _PanelSevenPageState();
}

class _PanelSevenPageState extends State<PanelSevenPage>
    with WidgetsBindingObserver {
  StreamSubscription<AuthState>? _subscription;
  PanelSevenSnapshot? _snapshot;
  bool _loading = true;
  bool _failed = false;
  int _generation = 0;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscription = widget.repository.changes.listen((_) {
      final snapshot = _snapshot;
      // Never use the event's session: a delayed logout event may carry B.
      if (_foreground && (snapshot == null || !widget.repository.isCurrent(snapshot))) {
        _load();
      }
    });
    _load();
  }

  Future<void> _load() async {
    if (!_foreground || !mounted) return;
    final generation = ++_generation;
    setState(() {
      _snapshot = null;
      _loading = true;
      _failed = false;
    });
    try {
      final snapshot = await widget.repository.load();
      if (!mounted || !_foreground || generation != _generation) return;
      if (!widget.repository.isCurrent(snapshot)) {
        throw StateError('session_changed');
      }
      setState(() {
        _snapshot = snapshot;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || !_foreground || generation != _generation) return;
      setState(() { _failed = true; _loading = false; });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _foreground = false;
      _generation++;
      setState(() { _snapshot = null; _loading = true; });
    } else if (state == AppLifecycleState.resumed) {
      _foreground = true;
      _load();
    }
  }

  @override
  void dispose() {
    _generation++;
    _subscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _help() {
    showDialog<void>(context: context, builder: (context) => AlertDialog(
      title: const Text('アカウント設定について'),
      content: const SingleChildScrollView(child: Text(
        '登録済みのログイン方法と本人の認証設定を確認します。'
        '連携済みの方法と、今回のログインに使った方法は別です。'
        '第一パスワードの有無は安全に確認できるAPIがないため推測しません。'
        '第二パスワードは重要情報用です。Face ID / Touch IDは端末内の本人確認で、'
        'Apple / Googleとの連携や電話番号の所有確認とは異なります。'
        'この画面からアカウント・会社・権限・パスワードは変更しません。'
        'マスター専用設定は従来のマスター本人確認の中で管理します。')),
      actions: [TextButton(onPressed: () => Navigator.pop(context),
          child: const Text('閉じる'))],
    ));
  }

  Widget _item(String title, String detail, {String? keyName}) => Card(
    child: ListTile(key: keyName == null ? null : ValueKey(keyName),
      title: Text(title), subtitle: Text(detail)),
  );

  String _provider(String provider) => switch (provider) {
    'google' => 'Google',
    'apple' => 'Apple',
    'phone' => '電話番号',
    'email' => 'メールアドレス',
    _ => 'その他の連携方法',
  };

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    return Scaffold(
      appBar: AppBar(title: const Text('アカウント設定'),
        actions: [IconButton(tooltip: '使い方', onPressed: _help,
            icon: const Icon(Icons.help_outline))]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _failed || snapshot == null
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('本人のアカウント情報を確認できませんでした。'),
                  TextButton(onPressed: _load, child: const Text('再読み込み')),
                ]))
              : ListView(padding: const EdgeInsets.all(16), children: [
                  _item('連携済みのログイン方法',
                    snapshot.providers.isEmpty ? '確認できません'
                        : snapshot.providers.map(_provider).join('・'),
                    keyName: 'account-providers'),
                  _item('現在のセッションの認証記録',
                    snapshot.sessionMethods.isEmpty ? '確認できません'
                        : snapshot.sessionMethods.map((method) =>
                            switch (method) {
                              'password' => 'パスワード認証',
                              'oauth' => '外部アカウント認証（提供元は特定できません）',
                              'otp' => 'ワンタイムコード認証',
                              'totp' => '認証アプリ',
                              _ => '組織アカウント認証',
                            }).join('・'),
                    keyName: 'account-session-methods'),
                  _item('第一パスワード', '設定状況は確認できません。'
                      'Google / Appleとの連携だけでは設定済みと判断しません。',
                      keyName: 'account-primary-password'),
                  _item('第二パスワード',
                      snapshot.secondaryConfigured == null ? '確認できません'
                          : snapshot.secondaryConfigured! ? '設定済み' : '未設定',
                      keyName: 'account-secondary-password'),
                  _item('メールアドレス',
                      snapshot.email?.isNotEmpty == true
                          ? '${snapshot.email}\n${snapshot.emailConfirmed ? "登録確認済み" : "未確認"}'
                          : '未登録'),
                  _item('電話番号',
                      snapshot.phone?.isNotEmpty == true
                          ? '${snapshot.phone}\n${snapshot.phoneConfirmed ? "登録確認済み（今回の番号所有確認ではありません）" : "未確認"}'
                          : '未登録',
                      keyName: 'account-phone'),
                  _item('Face ID / Touch ID',
                      'このアカウントの端末内設定：${snapshot.biometricEnabled == null ? "確認できません" : snapshot.biometricEnabled! ? "有効" : "未設定"}\n'
                      'この端末での利用：${snapshot.biometricAvailable == null ? "確認できません" : snapshot.biometricAvailable! ? "利用可能" : "利用できません"}\n'
                      '端末内の本人確認です。ログイン方法の連携や番号所有確認とは別です。',
                      keyName: 'panel-seven-biometric'),
                  const SizedBox(height: 12),
                  const Text('ログイン方法の追加', style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
                  _item('Appleを追加', '既存アカウントへのApple連携は準備中です。'
                      'Apple側・サーバー側の設定と本人再認証の確認が必要です。'
                      '今は登録済みの方法でログインしてください。'),
                  _item('電話番号を追加', '番号の所有確認方法を準備中です。'
                      '番号入力やFace IDだけで認証済みにはしません。'
                      'SMS送信や別アカウント作成は行いません。'),
                  _item('Google・メールを追加', '安全な追加手順を確認中です。'
                      '既存アカウントとの紐付けを維持するため、'
                      '新規登録から追加しないでください。'),
                  TextButton(onPressed: _load, child: const Text('最新の状態を確認')),
                ]),
    );
  }
}
