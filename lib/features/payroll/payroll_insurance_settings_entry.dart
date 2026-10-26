import 'package:flutter/material.dart';

class PayrollInsuranceEntryState {
  const PayrollInsuranceEntryState({required this.canOpen, required this.status,
    this.editing = false, this.referenceText, this.effectiveFrom});
  final bool canOpen, editing;
  final String status;
  final String? referenceText, effectiveFrom;
}

/// A view of the existing fixed-deduction state, not a second settings reader.
class PayrollInsuranceEntryController extends ValueNotifier<PayrollInsuranceEntryState> {
  PayrollInsuranceEntryController() : super(const PayrollInsuranceEntryState(
    canOpen: false, status: '設定状況を確認中'));
  Object? _owner;
  Future<void> Function()? _open;
  bool _disposed = false;

  void attach(Object owner, Future<void> Function() open) {
    if (_disposed) return;
    _owner = owner; _open = open;
  }

  void publish(Object owner, PayrollInsuranceEntryState next) {
    if (_disposed || !identical(_owner, owner)) return;
    if (value.canOpen != next.canOpen || value.status != next.status || value.editing != next.editing ||
        value.referenceText != next.referenceText || value.effectiveFrom != next.effectiveFrom) {
      value = next;
    }
  }

  void detach(Object owner) {
    if (identical(_owner, owner)) { _owner = null; _open = null; }
  }

  Future<void> open() async {
    if (_disposed || !value.canOpen) return;
    await _open?.call();
  }

  @override
  void dispose() {
    _disposed = true; _owner = null; _open = null;
    super.dispose();
  }
}

/// Shared entry outside earning/deduction cards and their unit selectors.
class PayrollInsuranceSettingsEntry extends StatelessWidget {
  const PayrollInsuranceSettingsEntry({super.key, required this.controller, this.enabled = true});
  final PayrollInsuranceEntryController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<PayrollInsuranceEntryState>(
    valueListenable: controller,
    builder: (context, value, _) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: FilledButton.icon(
            key: const ValueKey('insurance-settings-open'),
            onPressed: enabled && value.canOpen ? controller.open : null,
            icon: const Icon(Icons.settings_outlined),
            label: const Text('保険料を設定'),
          )),
          IconButton(tooltip: '保険料設定のヘルプ', icon: const Icon(Icons.help_outline),
            onPressed: () => showDialog<void>(context: context, builder: (context) => AlertDialog(
              title: const Text('保険料を設定'),
              content: const Text('支給・控除カードの外にある共通の入口です。時間・日・月単位の切替に関係なく、加入条件・平均月収・適用開始月を設定できます。入力中の控除修正は先に保存してください。適用月・保存済み平均月収もこの入口で確認できます。保険料は月額で、時間単位・日単位へ切り替えても追加計上しません。設定画面から戻ると同じ対象月の控除を読み直します。'),
              actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('閉じる'))],
            ))),
        ]),
        ExpansionTile(
          key: const ValueKey('insurance-settings-details'),
          initiallyExpanded: false,
          tilePadding: EdgeInsets.zero,
          title: Text(value.status, key: const ValueKey('insurance-settings-status'),
            style: Theme.of(context).textTheme.bodySmall),
          children: [
            if (value.effectiveFrom != null) Text('適用開始：${value.effectiveFrom}'),
            if (value.referenceText != null) Text(value.referenceText!),
            if (value.editing) const Text('入力中の修正を保存してから設定を開いてください。'),
          ],
        ),
      ]),
    ),
  );
}

