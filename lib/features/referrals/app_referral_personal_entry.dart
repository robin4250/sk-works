import 'package:flutter/material.dart';

import 'app_referral_page.dart';
import 'app_referral_repository.dart';

/// Personal access is decided by the existing server snapshot, never a local role.
class AppReferralPersonalEntry extends StatefulWidget {
  const AppReferralPersonalEntry({super.key, required this.repository});
  final AppReferralRepository repository;

  @override
  State<AppReferralPersonalEntry> createState() => _AppReferralPersonalEntryState();
}

class _AppReferralPersonalEntryState extends State<AppReferralPersonalEntry> {
  Map<String, dynamic>? _snapshot;
  bool _loading = true;
  bool _opening = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<bool> _load() async {
    final actor = widget.repository.currentActorId;
    try {
      if (actor == null) {
        throw StateError('login required');
      }
      final data = await widget.repository.load();
      if (!mounted) {
        return false;
      }
      if (widget.repository.currentActorId != actor) {
        throw StateError('actor changed');
      }
      setState(() { _snapshot = data; _error = null; });
      return data['enabled'] == true && data['can_invite'] == true;
    } catch (_) {
      if (mounted) {
        setState(() {
          _snapshot = null;
          _error = '招待の利用権限・ログイン情報・接続状態を確認できません。';
        });
      }
      return false;
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _open() async {
    if (_opening || _loading) {
      return;
    }
    setState(() => _opening = true);
    try {
      if (!await _load() || !mounted) {
        return;
      }
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => AppReferralPage(repository: widget.repository),
      ));
      if (mounted) {
        await _load();
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
    final allowed = data?['enabled'] == true && data?['can_invite'] == true;
    return Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ListTile(
        leading: const Icon(Icons.person_add_alt_1_outlined),
        title: const Text('SKOアプリ招待・自分の紹介履歴'),
        subtitle: Text(_loading ? '利用状態を確認中です。' : _error ??
          (data?['enabled'] != true ? '招待機能はOFFです（初期状態）。' :
            !allowed ? '現在のアカウントには招待を公開していません。' :
              data?['distribution_url_ready'] != true ? '配布URL未登録：履歴の確認のみ可能です。' :
                '名前・電話番号を入力しSMS作成画面を開く／自分の履歴を確認')),
        trailing: _loading || _opening ? const SizedBox(width: 20, height: 20,
          child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.chevron_right),
        onTap: allowed && !_opening && !_loading ? _open : null,
      ),
      if (!_loading && !allowed)
        TextButton(onPressed: _opening ? null : _load, child: const Text('利用状態を再確認')),
    ]));
  }
}
