import 'package:flutter/material.dart';
import 'payroll_statement_repository.dart';
import 'payroll_finalization_repository.dart';
import 'payroll_condition_warning.dart';

class PayrollFinalizationPanel extends StatefulWidget {
  const PayrollFinalizationPanel({super.key, required this.statement, required this.onSaved,
    required this.reloadStatement, this.repository, this.onBusyChanged, this.onVerificationRequired});
  final PayrollStatementRecord statement;
  final ValueChanged<PayrollStatementRecord> onSaved;
  final Future<PayrollStatementRecord?> Function() reloadStatement;
  final PayrollFinalizationRepository? repository;
  final ValueChanged<bool>? onBusyChanged;
  final ValueChanged<bool>? onVerificationRequired;
  @override
  State<PayrollFinalizationPanel> createState() => _PayrollFinalizationPanelState();
}
class _PayrollFinalizationPanelState extends State<PayrollFinalizationPanel> {
  late final PayrollFinalizationRepository? _repository;
  PayrollFinalizationStatus? _status;
  bool _busy = false;
  bool _uncertain = false;
  String? _error;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? PayrollFinalizationRepository.maybeCreate();
    _read();
  }
  @override
  void didUpdateWidget(covariant PayrollFinalizationPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.statement.id != widget.statement.id || oldWidget.statement.revision != widget.statement.revision ||
      oldWidget.statement.workflowState != widget.statement.workflowState) {
      _status = null;
      if (!_busy || oldWidget.statement.id != widget.statement.id) _read();
    }
  }
  Future<PayrollFinalizationStatus?> _read([PayrollStatementRecord? statement]) async {
    final generation = ++_generation;
    final repository = _repository;
    if (repository == null) return null;
    try {
      final status = await repository.read(statement ?? widget.statement);
      if (!mounted || generation != _generation) return null;
      setState(() { _status = status; if (!_uncertain) _error = null; });
      return status;
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() { _status = null; _error = '給与確定の状態を取得できません。権限・接続を確認して再読み込みしてください。'; });
      }
    }
    return null;
  }
  Future<void> _reload() async {
    if (_busy) return;
    setState(() => _busy = true);
    widget.onBusyChanged?.call(true);
    try {
      final fresh = await widget.reloadStatement();
      if (fresh == null) throw StateError('saved statement unavailable');
      final status = await _read(fresh);
      if (status == null || fresh.revision != status.revision ||
        (status.snapshotSaved && fresh.workflowState != 'finalized')) {
        throw StateError('saved statement not verified');
      }
      if (mounted) { setState(() { _uncertain = false; _error = null; }); widget.onVerificationRequired?.call(false); }
    } catch (_) {
      if (mounted) setState(() => _error = '保存結果を確認できません。再読み込みしてください。');
    } finally {
      if (mounted) setState(() => _busy = false);
      widget.onBusyChanged?.call(false);
    }
  }
  bool get _ready => !_uncertain && _status?.canFinalize == true && widget.statement.isDraft &&
    widget.statement.revision != null && widget.statement.revision == _status?.revision;
  Future<void> _finalize() async {
    final repository = _repository;
    if (_busy || !_ready || repository == null) return;
    final statement = widget.statement;
    final revision = _status!.revision;
    final generation = _generation;
    setState(() => _busy = true);
    widget.onBusyChanged?.call(true);
    bool sent = false;
    try {
      if (!await confirmPayrollConditions(context, payrollConditionWarnings(statement.detail)) ||
        !mounted || generation != _generation) return;
      final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
        title: const Text('給与を確定'),
        content: Text('${statement.workerName}\n${statement.monthLabel}\n差引支給額 ¥${statement.netPay}\n\nこの明細の条件・金額・確認記録を保存します。確定後の変更には別の修正処理が必要です。'),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('確認して確定'))])) ?? false;
      if (!confirmed || !mounted || generation != _generation) return;
      sent = true;
      final result = await repository.finalize(statement, revision);
      if (!mounted || generation != _generation) return;
      if (result.finalized) {
        widget.onSaved(result.statement!);
        setState(() { _status = null; _error = null; _uncertain = false; });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('給与明細を確定して保存しました')));
      } else {
        widget.onVerificationRequired?.call(true);
        setState(() { _status = null; _uncertain = true; _error = '再計算で給与が変わりました。再読み込みし、内容と確認をやり直してください。'; });
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        if (sent) widget.onVerificationRequired?.call(true);
        setState(() { _status = null; _uncertain = sent;
          _error = sent ? '確定結果を確認できません。再送せず、再読み込みして保存状態を確認してください。' : '確認操作を完了できませんでした。'; });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
      widget.onBusyChanged?.call(false);
    }
  }
  @override
  Widget build(BuildContext context) {
    if (_status == null && _error == null) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Column(children: [
      if (_error != null) Text(_error!),
      if (_status?.canFinalize == true && !_ready && _error == null)
        const Text('給与の版が変わっています。再読み込みして内容を確認してください。'),
      if (_ready) FilledButton(onPressed: _busy ? null : _finalize, child: const Text('給与を確定')),
      if (_error != null || (_status?.canFinalize == true && !_ready))
        TextButton(onPressed: _busy ? null : _reload, child: const Text('保存状態を再読み込み')),
      IconButton(tooltip: '給与確定の使い方', icon: const Icon(Icons.help_outline),
        onPressed: () => showDialog<void>(context: context, builder: (context) => AlertDialog(
          title: const Text('給与確定の使い方'),
          content: const Text('月の確認登録と、明細の保存確定は別の操作です。全確認者が現在の版を確認した自動計算の下書きを、編集権限のある人が1件ずつ確定します。保存後はその時点の明細を表示します。結果不明時は再送せず保存状態を再読み込みしてください。'),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('閉じる'))]))),
    ]));
  }
}
