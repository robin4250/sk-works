import 'dart:async';

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
    this.isCurrent,
    this.invalidations,
    this.onInvalidate,
    this.onShown,
  });

  final AttentionCenterItem item;
  final Future<void> Function(BuildContext context) openTarget;
  final Future<bool> Function()? canOpenTarget;
  final bool Function()? isCurrent;
  final Stream<void>? invalidations;
  final VoidCallback? onInvalidate;
  final Future<void> Function()? onShown;

  @override
  State<NotificationExplanationPage> createState() =>
      _NotificationExplanationPageState();
}

String notificationExplanationSteps(String? actionKey) {
  final steps = switch (actionKey) {
    'company_profile_review' =>
      '1. 連携会社の旧情報と更新候補を確認します。\n2.「開く」で対象の会社情報更新確認へ進みます。\n3. 更新または見送りを選びます。確認前に登録内容は変わらず、旧情報・契約単価・過去帳票は保持します。',
    'company_link_request' =>
      '1. 申請元の会社と連携の種類、開始月を確認します。\n2.「開く」で連携申請の詳細へ進みます。\n3. 内容を確認し、承認または却下を選びます。承認前に会社連携は成立しません。',
    'site_payment_agreement' =>
      '1. 通知の宛先会社・現在の権限と利用設定を確認して、対象の現場契約を開きます。\n2.「開く」で単価・手当・適用開始日と帳票を確認します。\n3. 送信側は押印して送信し、受信側は内容を確認して押印承認します。変更案の承認までは現行契約を維持します。',
    'site_share_approval' =>
      '1. 共有元の会社と現場を確認します。\n2.「開く」で共有現場の詳細へ進みます。\n3. 内容を確認し、現場の受入れを判断します。現場の受入れと契約単価への合意は別の操作です。',
    'invoice_approval' =>
      '1. 請求の対象会社・対象月を確認します。\n2.「開く」で請求明細と金額を確認します。\n3. 必要な修正や承認は請求書画面で行います。',
    'expense_review_request' =>
      '1. 申請された経費の内容を確認します。\n2.「開く」で通知に対応する申請だけを表示します。\n3. 承認・振り分けは経費一覧で行います。通知を見ただけでは承認しません。',
    'expense_review_completed' =>
      '1. 経費の振り分けが完了したお知らせです。\n2.「開く」で通知作成時の確定内容・負担先・精算方法を確認します。\n3. 現在の状態は経費一覧で確認してください。給与精算や現金精算の選択は、実際の振込・支払完了とは別です。',
    'payroll_review' =>
      '1. 通知の給与対象月を確認します。\n2.「開く」で本人確認後、対象月の給料一覧へ進みます。\n3. 内容の確認や承認は給料一覧で行います。',
    null || '' => 'この通知の内容をご確認ください。操作が必要なリンクはありません。',
    _ => '1. この通知の内容と対象を確認します。\n2.「開く」から対象画面へ進みます。\n3. 対象画面で内容を確認し、必要な操作を行います。',
  };
  return '$steps\n戻ると、この説明ページに戻れます。';
}

class _NotificationExplanationPageState
    extends State<NotificationExplanationPage>
    with WidgetsBindingObserver {
  StreamSubscription<void>? _subscription;
  bool _closed = false;
  bool get _current =>
      mounted && !_closed && (widget.isCurrent?.call() ?? true);
  void _close() {
    if (mounted && !_closed) {
      setState(() => _closed = true);
      widget.onInvalidate?.call();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _close();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    super.dispose();
  }

  bool _opening = false;
  String? _error;
  bool _available = false;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscription = widget.invalidations?.listen(
      (_) => _close(),
      onError: (Object _) => _close(),
    );
    _closed = !(widget.isCurrent?.call() ?? true);
    if (!_closed) _checkAvailability();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!_current || widget.onShown == null) return;
      try {
        await widget.onShown!();
      } catch (_) {
        if (_current) setState(() => _error = '通知の既読状態を保存できませんでした。');
      }
    });
  }

  Future<void> _checkAvailability() async {
    try {
      final available = await widget.canOpenTarget?.call() ?? true;
      if (_current) {
        setState(() {
          _available = available;
          _checking = false;
        });
      }
    } catch (_) {
      if (_current) {
        setState(() {
          _available = false;
          _checking = false;
        });
      }
    }
  }

  Future<void> _open() async {
    if (!_current || _opening) return;
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      if (!(await widget.canOpenTarget?.call() ?? true)) {
        if (_current) setState(() => _available = false);
        return;
      }
      if (!mounted || !_current) return;
      await widget.openTarget(context);
    } catch (_) {
      if (_current) setState(() => _error = '対象を開けません。削除・権限・機能の利用状態を確認してください。');
    } finally {
      if (_current) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    if (_closed || !(widget.isCurrent?.call() ?? true)) {
      return Scaffold(
        appBar: AppBar(title: Text(SkoLanguageController.tr('お知らせ'))),
        body: const Center(child: Text('通知一覧を開き直してください。')),
      );
    }
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
              notificationExplanationSteps(item.actionKey),
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
