import 'package:flutter/material.dart';
import '../../international/language_controller.dart';
import 'account_deletion_repository.dart';
import 'account_deletion_status.dart';

class AccountDeletionPage extends StatefulWidget {
  const AccountDeletionPage({super.key, this.loadStatus});
  final Future<AccountDeletionStatus> Function()? loadStatus;
  @override
  State<AccountDeletionPage> createState() => _AccountDeletionPageState();
}

class _AccountDeletionPageState extends State<AccountDeletionPage> {
  AccountDeletionStatus? _status;
  bool _loading = true;
  bool _failed = false;
  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _failed = false; _status = null; });
    try {
      final loader = widget.loadStatus ?? AccountDeletionRepository.maybeCreate()?.load;
      if (loader == null) { throw StateError('status_unavailable'); }
      final status = await loader();
      if (mounted) { setState(() { _status = status; _loading = false; }); }
    } catch (_) {
      if (mounted) { setState(() { _failed = true; _loading = false; }); }
    }
  }

  String _label(AccountDeletionState state) => switch (state) {
    AccountDeletionState.noRequest => '削除申請はありません',
    AccountDeletionState.requested => '削除申請受付済み（削除未完了）',
    AccountDeletionState.processing => '削除処理中（削除未完了）',
    AccountDeletionState.failed => '削除処理の確認が必要です',
    AccountDeletionState.completed => '削除処理完了',
    AccountDeletionState.unknown => '削除申請の状態を確認できません',
  };

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: SkoLanguageController.pack,
    builder: (context, _) => Scaffold(
    appBar: AppBar(title: Text(SkoLanguageController.tr('アカウント削除'))),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      Text(SkoLanguageController.tr('アカウント削除の受付は現在停止しています。')),
      const SizedBox(height: 12),
      Text(SkoLanguageController.tr('給与・請求・署名済み日報など会社に必要な記録の保護を確認中です。ここでは削除を実行できません。')),
      const SizedBox(height: 24),
      if (_loading) const Center(child: CircularProgressIndicator())
      else if (_failed) Text(SkoLanguageController.tr('削除申請の状態を確認できません'))
      else if (_status != null) Text(SkoLanguageController.tr(_label(_status!.state))),
      if (_status?.dueAt != null) ...[
        const SizedBox(height: 8),
        Text(SkoLanguageController.tr('処理予定日は完了を保証するものではありません。')),
      ],
      const SizedBox(height: 16),
      OutlinedButton(onPressed: _loading ? null : _load,
        child: Text(SkoLanguageController.tr('再読み込み'))),
    ]),
  ));
}
