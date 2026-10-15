import 'package:flutter/material.dart';

import '../settings/master_protected_page.dart';
import 'app_referral_page.dart';
import 'app_referral_repository.dart';

/// The master-only snapshot authorizes this hub independently of its caller.
class AppReferralMasterEntry extends StatefulWidget {
  const AppReferralMasterEntry({super.key, required this.repository});
  final AppReferralRepository repository;

  @override
  State<AppReferralMasterEntry> createState() => _AppReferralMasterEntryState();
}

class _AppReferralMasterEntryState extends State<AppReferralMasterEntry> {
  Map<String, dynamic>? _snapshot;
  bool _loading = true;
  bool _opening = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _snapshot = null; _error = null; });
    final actor = widget.repository.currentActorId;
    try {
      if (actor == null) {
        throw StateError('login required');
      }
      final data = await widget.repository.load(master: true);
      if (!mounted) {
        return;
      }
      if (widget.repository.currentActorId != actor) {
        throw StateError('actor changed');
      }
      setState(() => _snapshot = data);
    } catch (_) {
      if (mounted) {
        setState(() => _error = '紹介管理を利用できません。Master権限と接続状態を確認してください。');
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _open({required bool master}) async {
    if (_opening || _loading) {
      return;
    }
    final actor = widget.repository.currentActorId;
    setState(() => _opening = true);
    try {
      final data = await widget.repository.load(master: true);
      if (!mounted) {
        return;
      }
      if (actor == null || widget.repository.currentActorId != actor) {
        throw StateError('actor changed');
      }
      setState(() => _snapshot = data);
      if (!master && (data['enabled'] != true || data['can_invite'] != true)) {
        return;
      }
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => MasterProtectedPage(
          title: master ? 'SKO紹介設定・全体履歴' : 'SKOアプリ招待',
          child: AppReferralPage(repository: widget.repository, master: master),
        ),
      ));
      if (mounted) {
        await _load();
      }
    } catch (_) {
      if (mounted) {
        setState(() { _snapshot = null; _error = '紹介管理の権限または利用状態を確認できません。'; });
      }
    } finally {
      if (mounted) {
        setState(() => _opening = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _snapshot;
    return Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('SKOアプリ招待・紹介管理', style: TextStyle(fontWeight: FontWeight.bold)),
        if (_loading) const LinearProgressIndicator()
        else if (_error != null) ...[
          Text(_error!),
          TextButton(onPressed: _opening ? null : _load, child: const Text('再読み込み')),
        ] else if (data != null) ...[
          Text(data['enabled'] == true ? '招待機能：ON' : '招待機能：OFF（初期状態）'),
          Text(data['public_enabled'] == true ? '一般公開：ON' : '一般公開：OFF'),
          if (data['distribution_url_ready'] != true)
            const Text('正式な配布URLが未登録です。仮URLでは送信しません。'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.admin_panel_settings_outlined),
            title: const Text('紹介設定・全体履歴'),
            subtitle: const Text('Masterのみ：機能ON／OFF・配布URL・紹介記録'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _opening ? null : () => _open(master: true),
          ),
          if (data['enabled'] == true && data['can_invite'] == true)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person_add_alt_1_outlined),
              title: const Text('SKOアプリ招待'),
              subtitle: const Text('名前・電話番号を入力してSMS作成画面を開く'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _opening ? null : () => _open(master: false),
            ),
          const Text('紹介元確定・登録完了通知・ポイント付与は未接続です。使い方は開いた画面の？から確認できます。'),
        ],
      ],
    )));
  }
}
