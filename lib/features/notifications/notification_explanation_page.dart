import 'package:flutter/material.dart';

import '../../international/language_controller.dart';
import 'attention_center_item.dart';

/// A durable explanation; opening it never performs the requested operation.
class NotificationExplanationPage extends StatefulWidget {
  const NotificationExplanationPage({
    super.key,
    required this.item,
    required this.openTarget,
    this.canOpenTarget,
  });

  final AttentionCenterItem item;
  final Future<void> Function(BuildContext context) openTarget;
  final Future<bool> Function()? canOpenTarget;

  @override
  State<NotificationExplanationPage> createState() =>
      _NotificationExplanationPageState();
}

class _NotificationExplanationPageState
    extends State<NotificationExplanationPage> {
  bool _opening = false;
  String? _error;
  bool _available = false;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _checkAvailability();
  }

  Future<void> _checkAvailability() async {
    try {
      final available = await widget.canOpenTarget?.call() ?? true;
      if (mounted)
        setState(() {
          _available = available;
          _checking = false;
        });
    } catch (_) {
      if (mounted)
        setState(() {
          _available = false;
          _checking = false;
        });
    }
  }

  Future<void> _open() async {
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      if (!(await widget.canOpenTarget?.call() ?? true)) {
        if (mounted) setState(() => _available = false);
        return;
      }
      await widget.openTarget(context);
    } catch (_) {
      if (mounted) setState(() => _error = '対象を開けません。削除・権限・機能の利用状態を確認してください。');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    final item = widget.item;
    final hasTarget = item.actionKey?.isNotEmpty == true;
    return Scaffold(
      appBar: AppBar(title: Text(SkoLanguageController.tr('通知の説明'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            SkoLanguageController.tr('このページは右上のベルマークから何度も見れます！'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 20),
          Text(item.title, style: Theme.of(context).textTheme.headlineSmall),
          if (item.body.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(item.body),
          ],
          if (item.targetName?.isNotEmpty == true) ...[
            const SizedBox(height: 12),
            Text(item.targetName!),
          ],
          const Divider(height: 32),
          Text(
            SkoLanguageController.tr('操作の流れ'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            SkoLanguageController.tr(
              hasTarget
                  ? '1. この通知の内容と対象を確認します。\n2.「開く」から対象画面へ進みます。\n3. 対象画面で内容を確認し、必要な操作を行います。\n戻ると、この説明ページに戻れます。'
                  : 'この通知の内容をご確認ください。操作が必要なリンクはありません。',
            ),
          ),
          const SizedBox(height: 12),
          Text(SkoLanguageController.tr('このページを見ただけで、承認・押印・送信・設定変更は行われません。')),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(SkoLanguageController.tr(_error!)),
          ],
          if (hasTarget && _checking) const LinearProgressIndicator(),
          if (hasTarget && !_checking && !_available)
            Text(SkoLanguageController.tr('現在この機能は利用できません。通知の履歴は引き続き確認できます。')),
          if (hasTarget && !_checking && _available) ...[
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _opening ? null : _open,
              icon: const Icon(Icons.open_in_new),
              label: Text(SkoLanguageController.tr(_opening ? '確認中' : '開く')),
            ),
          ],
        ],
      ),
    );
  }
}
