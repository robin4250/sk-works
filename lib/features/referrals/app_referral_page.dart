import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_referral_repository.dart';

class AppReferralPage extends StatefulWidget {
  const AppReferralPage({
    super.key,
    required this.repository,
    this.master = false,
  });
  final AppReferralRepository repository;
  final bool master;
  @override
  State<AppReferralPage> createState() => _AppReferralPageState();
}

class _AppReferralPageState extends State<AppReferralPage> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _url = TextEditingController();
  Map<String, dynamic>? _snapshot;
  String? _error;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await widget.repository.load(master: widget.master);
      if (!mounted) return;
      setState(() {
        _snapshot = data;
        _url.text = data['distribution_url']?.toString() ?? '';
        _error = null;
      });
    } catch (_) {
      if (mounted)
        setState(() => _error = '招待機能を読み込めません。サーバー設定・利用権限を確認してください。');
    }
  }

  Future<void> _send() async {
    setState(() => _busy = true);
    try {
      final result = await widget.repository.prepare(_name.text, _phone.text);
      final uri = Uri(
        scheme: 'sms',
        path: result['phone'].toString(),
        queryParameters: {'body': result['message'].toString()},
      );
      if (!await launchUrl(uri)) throw StateError('SMS作成画面を開けませんでした。');
      await widget.repository.recordComposerOpened(result['id'].toString());
      await _load();
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('招待を準備できません。名前・電話番号・配布URL・利用権限を確認してください。'),
          ),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await widget.repository.saveSettings(
        enabled: _snapshot!['enabled'] == true,
        publicEnabled: _snapshot!['public_enabled'] == true,
        notifyMaster: _snapshot!['notify_master'] == true,
        url: _url.text,
      );
      await _load();
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('設定を保存できませんでした。')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _snapshot;
    final rows = data?['invitations'] as List? ?? const [];
    final rankings = data?['rankings'] as List? ?? const [];
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.master ? 'SKO ID管理・紹介記録' : 'SKOアプリ招待'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('SKOアプリ招待の使い方'),
                content: const Text(
                  '名前・電話番号を入力して送信を押すとSMS作成画面が開きます。送信・配達は確認できません。社員の初回登録とは別の紹介機能です。新規登録の確認後、登録前の最終招待者を記録します。ポイント数・使い道は未定です。履歴はこの画面で確認できます。',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('閉じる'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_error != null) ...[
              Text(_error!),
              TextButton(onPressed: _load, child: const Text('再読み込み')),
            ],
            if (data == null && _error == null)
              const Center(child: CircularProgressIndicator()),
            if (data != null) ...[
              if (widget.master) ...[
                if (data['attribution_connected'] != true)
                  const Text(
                    '新規登録者の本人確認・紹介元確定・ポイント付与・登録完了通知は未接続です。登録済みとは表示しません。',
                  ),
                for (final entry in {
                  'enabled': '招待機能',
                  'public_enabled': '一般ユーザーへ公開',
                  'notify_master': '登録完了をマスターへ通知',
                }.entries)
                  SwitchListTile(
                    title: Text(entry.value),
                    value: data[entry.key] == true,
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => data[entry.key] = value),
                  ),
                TextField(
                  controller: _url,
                  decoration: const InputDecoration(
                    labelText: '配布URL（TestFlight／公開後のストア）',
                  ),
                ),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: const Text('設定を保存'),
                ),
              ] else if (data['can_invite'] == true) ...[
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: '名前'),
                ),
                TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: '電話番号'),
                ),
                if (data['distribution_url_ready'] != true)
                  const Text('配布URLが未登録です。管理者へTestFlight URLの設定を依頼してください。'),
                FilledButton(
                  onPressed: _busy || data['distribution_url_ready'] != true
                      ? null
                      : _send,
                  child: const Text('送信'),
                ),
                const Text('SMS作成画面を開きます。送信・配達を保証する表示ではありません。'),
              ] else
                const Text('現在、招待機能は利用できません。'),
              const Divider(),
              const Text('招待履歴'),
              for (final row in rows)
                ListTile(
                  title: Text(
                    '${row['recipient_name']}　${row['recipient_phone']}',
                  ),
                  subtitle: Text(
                    '${referralJapanTime(row['created_at'].toString())}\n${row['state_label']}'
                    '${widget.master ? '\n招待者: ${row['inviter_name']}／${row['company_name']}' : ''}',
                  ),
                ),
              if (rows.isEmpty) const Text('招待履歴はありません。'),
              if (widget.master) ...[
                const Divider(),
                const Text('紹介ランキング（ポイント利用方法・付与数は未設定）'),
                for (var i = 0; i < rankings.length; i++)
                  ListTile(
                    title: Text(
                      '${i + 1}位　${rankings[i]['name']}　${rankings[i]['company_name']}',
                    ),
                    subtitle: Text(
                      '登録 ${rankings[i]['registration_count']}人／ポイント ${rankings[i]['points'] ?? '未設定'}',
                    ),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
