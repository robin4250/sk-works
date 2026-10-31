import 'dart:async';

import 'payroll_condition_warning.dart';

import 'package:flutter/material.dart';

import '../notifications/notification_bell.dart';
import '../../international/language_controller.dart';
import 'payroll_review_repository.dart';
import 'payroll_statements_page.dart';

class PayrollReviewPage extends StatefulWidget {
  const PayrollReviewPage({
    super.key,
    this.initialMonth,
    this.onOpenSettings,
    this.onOpenTaxRates,
    this.onOpenCommonAllowances,
    this.repository,
  });

  final FutureOr<void> Function()? onOpenSettings;
  final FutureOr<void> Function()? onOpenTaxRates;
  final FutureOr<void> Function()? onOpenCommonAllowances;
  @visibleForTesting
  final PayrollReviewRepository? repository;

  final DateTime? initialMonth;

  @override
  State<PayrollReviewPage> createState() => _PayrollReviewPageState();
}

class _PayrollReviewPageState extends State<PayrollReviewPage> {
  late final PayrollReviewRepository? _repository;
  PayrollReviewWorkspace? _workspace;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  bool _loading = true;
  bool _saving = false;
  String? _error;
  int _loadGeneration = 0;
  bool _openingSettings = false;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? PayrollReviewRepository.maybeCreate();
    final initial = widget.initialMonth;
    if (initial != null) {
      _month = DateTime(initial.year, initial.month);
    }
    _load();
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    final repository = _repository;
    if (repository == null) {
      setState(() {
        _loading = false;
        _error = SkoLanguageController.isEnglish
            ? 'Payroll review is unavailable.'
            : '給料一覧を利用できません。';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final workspace = await repository.loadWorkspace(_month);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _workspace = workspace;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _openSettings(FutureOr<void> Function() open) async {
    if (_openingSettings) return;
    _openingSettings = true;
    try {
      await open();
      if (mounted) await _load();
    } finally {
      _openingSettings = false;
    }
  }

  Future<void> _setReviewCheck(PayrollReviewItem item, bool checked) async {
    final repository = _repository;
    if (repository == null) return;
    await repository.setReviewCheck(
      statementId: item.statement.id,
      revision: item.revision,
      checked: checked,
    );
    await _load();
  }

  Future<void> _confirm() async {
    final repository = _repository;
    final workspace = _workspace;
    if (repository == null || workspace == null || !workspace.canConfirm) {
      return;
    }
    if (workspace.items.isEmpty) return;
    if (workspace.items.any((item) => !item.reviewChecked)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            SkoLanguageController.isEnglish
                ? 'Review every employee payslip before confirming.'
                : '全従業員の給与明細を確認してから登録してください',
          ),
        ),
      );
      return;
    }
    final warnings = [
      for (final item in workspace.items)
        for (final warning in payrollConditionWarnings(item.statement.detail))
          '${item.statement.workerName}：$warning',
    ];
    if (!await confirmPayrollConditions(context, warnings) || !mounted) return;
    setState(() => _saving = true);
    try {
      await repository.confirmMonth(_month);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            SkoLanguageController.isEnglish
                ? 'Your review is registered.'
                : '自分の確認を登録しました。全確認者の確認後に完了します',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${SkoLanguageController.isEnglish ? 'Could not confirm' : '確認を登録できませんでした'}: $error',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setHiddenFromSubAdmin(
    PayrollReviewWorkerVisibility worker,
    bool hidden,
  ) async {
    final repository = _repository;
    final workspace = _workspace;
    if (repository == null ||
        workspace == null ||
        !workspace.isAdmin ||
        !const {'owner', 'admin'}.contains(workspace.role)) {
      return;
    }
    await repository.setManagerVisibility(
      workerId: worker.workerId,
      visible: !hidden,
    );
    await _load();
  }

  Future<void> _moveMonth(int offset) async {
    setState(() => _month = DateTime(_month.year, _month.month + offset));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    final workspace = _workspace;
    final items = workspace?.items ?? const <PayrollReviewItem>[];
    return Scaffold(
      appBar: AppBar(
        title: Text(
          SkoLanguageController.isEnglish ? 'Payroll Review' : '給料一覧',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: const [SkoNotificationBell()],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (widget.onOpenSettings != null ||
                widget.onOpenTaxRates != null ||
                widget.onOpenCommonAllowances != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final buttonWidth = (constraints.maxWidth - 20) / 3;
                    final taxSize = (buttonWidth - 38) / 4;
                    final textSize = (buttonWidth - 12) / 6;
                    final fittingSize = taxSize < textSize ? taxSize : textSize;
                    final fontSize =
                        (fittingSize /
                                MediaQuery.textScalerOf(context).scale(1))
                            .clamp(1.0, 14.0);
                    final buttonStyle = OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      textStyle: TextStyle(fontSize: fontSize),
                    );
                    return Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: OutlinedButton.icon(
                              key: const ValueKey('payroll-tax-rates-entry'),
                              style: buttonStyle,
                              onPressed: widget.onOpenTaxRates == null
                                  ? null
                                  : () => _openSettings(widget.onOpenTaxRates!),
                              icon: const Icon(
                                Icons.percent_outlined,
                                size: 18,
                              ),
                              label: Text(
                                SkoLanguageController.tr('税率設定'),
                                maxLines: 1,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: OutlinedButton(
                              key: const ValueKey(
                                'payroll-common-allowances-entry',
                              ),
                              style: buttonStyle,
                              onPressed: widget.onOpenCommonAllowances == null
                                  ? null
                                  : () => _openSettings(
                                      widget.onOpenCommonAllowances!,
                                    ),
                              child: Text(
                                SkoLanguageController.tr('社内共通手当'),
                                maxLines: 1,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: OutlinedButton(
                              key: const ValueKey(
                                'payroll-individual-settings-entry',
                              ),
                              style: buttonStyle,
                              onPressed: widget.onOpenSettings == null
                                  ? null
                                  : () => _openSettings(widget.onOpenSettings!),
                              child: Text(
                                SkoLanguageController.tr('個別給料設定'),
                                maxLines: 1,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(_error!, textAlign: TextAlign.center),
                      ),
                    )
                  : workspace == null
                  ? const SizedBox.shrink()
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                        children: [
                          PayrollConditionWarning(
                            warnings: [
                              for (final item in items)
                                for (final warning in payrollConditionWarnings(
                                  item.statement.detail,
                                ))
                                  '${item.statement.workerName}：$warning',
                            ],
                          ),
                          Row(
                            children: [
                              IconButton(
                                onPressed: () => _moveMonth(-1),
                                icon: const Icon(Icons.chevron_left),
                              ),
                              Expanded(
                                child: Text(
                                  SkoLanguageController.isEnglish
                                      ? '${_month.month}/${_month.year}'
                                      : '${_month.year}年${_month.month}月',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () => _moveMonth(1),
                                icon: const Icon(Icons.chevron_right),
                              ),
                            ],
                          ),
                          if (workspace.isAdmin &&
                              const {
                                'owner',
                                'admin',
                              }.contains(workspace.role)) ...[
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                SkoLanguageController.isEnglish
                                    ? 'Active employees: ${workspace.workers.length} / Monthly payslips: ${items.length}'
                                    : '在籍社員 ${workspace.workers.length}名 ／ 当月明細 ${items.length}件',
                                key: const ValueKey('payroll-roster-counts'),
                              ),
                            ),
                            if (items.every(
                                  (item) => item.workerId.isNotEmpty,
                                ) &&
                                workspace.workers.any(
                                  (worker) => !items.any(
                                    (item) => item.workerId == worker.workerId,
                                  ),
                                ))
                              Card(
                                child: ExpansionTile(
                                  key: const ValueKey(
                                    'payroll-roster-without-statements',
                                  ),
                                  title: Text(
                                    SkoLanguageController.isEnglish
                                        ? 'Active employees without a payslip this month'
                                        : 'この月の明細がない在籍社員',
                                  ),
                                  subtitle: Text(
                                    SkoLanguageController.isEnglish
                                        ? 'Payroll settings and monthly payslips are separate lists. Check the target month, payroll settings and attendance.'
                                        : '個別給与設定と当月の明細は対象が異なります。対象月・給与設定・勤務実績を確認してください。',
                                  ),
                                  children: [
                                    for (final worker in workspace.workers)
                                      if (!items.any(
                                        (item) =>
                                            item.workerId == worker.workerId,
                                      ))
                                        ListTile(
                                          title: Text(worker.workerName),
                                          subtitle: Text(
                                            SkoLanguageController.isEnglish
                                                ? 'No payslip for this month'
                                                : 'この月の給与明細がありません',
                                          ),
                                        ),
                                  ],
                                ),
                              ),
                            const SizedBox(height: 8),
                            Card(
                              child: ExpansionTile(
                                title: Text(
                                  SkoLanguageController.isEnglish
                                      ? 'Hide from sub-admins'
                                      : 'サブ管理者に見せない従業員',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                subtitle: Text(
                                  SkoLanguageController.isEnglish
                                      ? 'Check only the employees sub-admins must not see.'
                                      : '非表示にする従業員だけチェックしてください',
                                ),
                                children: [
                                  for (final worker in workspace.workers)
                                    CheckboxListTile(
                                      value: !worker.visibleToManager,
                                      title: Text(worker.workerName),
                                      onChanged: (value) =>
                                          _setHiddenFromSubAdmin(
                                            worker,
                                            value ?? false,
                                          ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          if (items.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(32),
                              child: Text(
                                SkoLanguageController.isEnglish
                                    ? 'No payslips have been issued for this month yet.'
                                    : 'この月の給与明細はまだありません',
                                textAlign: TextAlign.center,
                              ),
                            )
                          else
                            for (final item in items)
                              Card(
                                child: ListTile(
                                  onTap: () async {
                                    await Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) =>
                                            PayrollStatementPreviewPage(
                                              statement: item.statement,
                                              allowFinalization: true,
                                            ),
                                      ),
                                    );
                                    if (mounted) await _load();
                                  },
                                  leading: workspace.canConfirm
                                      ? Checkbox(
                                          value: item.reviewChecked,
                                          onChanged: (value) => _setReviewCheck(
                                            item,
                                            value ?? false,
                                          ),
                                        )
                                      : null,
                                  title: Text(
                                    item.statement.workerName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  subtitle: Text(
                                    item.reviewConfirmed
                                        ? (SkoLanguageController.isEnglish
                                              ? 'Confirmed'
                                              : '確認済み')
                                        : (SkoLanguageController.isEnglish
                                              ? 'Unconfirmed'
                                              : '未確認'),
                                    style: TextStyle(
                                      color: item.reviewConfirmed
                                          ? Colors.green
                                          : Theme.of(context).colorScheme.error,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  trailing: Text(
                                    _yen(item.statement.netPay),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ),
                          if (workspace.canConfirm && items.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: _saving ? null : _confirm,
                              icon: const Icon(Icons.verified_outlined),
                              label: Text(
                                _saving
                                    ? (SkoLanguageController.isEnglish
                                          ? 'Confirming…'
                                          : '登録中…')
                                    : (SkoLanguageController.isEnglish
                                          ? 'Confirm after reviewing all'
                                          : '確認を登録'),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _yen(int value) {
    final digits = value.abs().toString();
    final groups = <String>[];
    for (var end = digits.length; end > 0; end -= 3) {
      final start = (end - 3).clamp(0, digits.length);
      groups.insert(0, digits.substring(start, end));
    }
    return '${value < 0 ? '-' : ''}¥${groups.join(',')}';
  }
}
