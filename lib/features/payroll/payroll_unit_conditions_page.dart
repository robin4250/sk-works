import 'package:flutter/material.dart';

import '../../international/language_controller.dart';
import 'payroll_unit_conditions_repository.dart';
import 'payroll_unit_item_editor.dart';
import 'payroll_company_common_card.dart';

class PayrollUnitConditionsPage extends StatefulWidget {
  const PayrollUnitConditionsPage({
    super.key,
    required this.repository,
    required this.companyId,
    required this.workerId,
    this.embedded = false,
    this.section,
    this.unit,
    this.onValidationSelection,
    this.editorController,
    this.externalFooter = false,
  });
  final PayrollUnitConditionsRepository repository;
  final String companyId;
  final String workerId;
  final bool embedded;
  final PayrollUnitEditorController? editorController;
  final bool externalFooter;
  final PayrollItemSection? section;
  final PayrollItemUnit? unit;
  final void Function(PayrollItemSection, PayrollItemUnit)? onValidationSelection;
  @override
  State<PayrollUnitConditionsPage> createState() =>
      _PayrollUnitConditionsPageState();
}

class _PayrollUnitConditionsPageState extends State<PayrollUnitConditionsPage> {
  late DateTime _month;
  PayrollUnitConditions? _value;
  String? _error;
  bool _loading = true;
  bool _saving = false;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _load();
  }

  @override
  void didUpdateWidget(covariant PayrollUnitConditionsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workerId != widget.workerId || oldWidget.companyId != widget.companyId) {
      _load();
    }
  }

  String get _monthKey =>
      '${_month.year}-${_month.month.toString().padLeft(2, '0')}-01';
  Future<void> _moveMonth(int offset) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(SkoLanguageController.tr('月を変更しますか？未登録の入力内容は保存されません。')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(SkoLanguageController.tr('キャンセル')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(SkoLanguageController.tr('月を変更')),
          ),
        ],
      ),
    );
    if (!mounted || accepted != true) return;
    _month = DateTime(_month.year, _month.month + offset);
    await _load();
  }

  Future<void> _load() async {
    widget.editorController?.invalidate();
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (!await widget.repository.available()) {
        throw StateError('not available');
      }
      final value = await widget.repository.load(
        widget.companyId,
        widget.workerId,
        _monthKey,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _value = value;
        _loading = false;
        _saving = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = '単位別設定を取得できません。サーバー準備状況を確認してください。';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    String tr(String x) => SkoLanguageController.tr(x);
    final body = _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(tr(_error!)),
                  TextButton(onPressed: _load, child: Text(tr('再読み込み'))),
                ],
              ),
            )
          : Column(
              mainAxisSize: widget.embedded ? MainAxisSize.min : MainAxisSize.max,
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: _saving ? null : () => _moveMonth(-1),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      if (!_value!.canEdit)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(tr('閲覧のみ')),
                        ),
                      Expanded(
                        child: Text(
                          '${_month.year}/${_month.month} ${tr('対象月')}',
                          textAlign: TextAlign.center,
                        ),
                      ),
                      IconButton(
                        onPressed: _saving ? null : () => _moveMonth(1),
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                ),
                if (_value!.companyCommonItems.isNotEmpty)
                  PayrollCompanyCommonCard(
                    key: ValueKey('${widget.companyId}/${widget.workerId}/${_value!.month}/${_value!.companyCommonSourceJson}'),
                    items: _value!.companyCommonItems,
                    canEdit: _value!.canEdit && !_saving,
                    section: widget.section, unit: widget.unit,
                    onReload: _load,
                    onSave: (hours) async {
                      final generation = _generation;
                      final company = widget.companyId;
                      final worker = widget.workerId;
                      final current = _value!;
                      setState(() => _saving = true);
                      try {
                        final saved = await widget.repository.saveCommonHours(company, worker, current, hours);
                        if (!mounted || generation != _generation || widget.companyId != company || widget.workerId != worker) return;
                        setState(() => _value = saved);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('共通手当の時間数を保存し、対象月の給与を再計算しました'))));
                      } finally {
                        if (mounted && generation == _generation) setState(() => _saving = false);
                      }
                    },
                  ),
                Flexible(
                  fit: widget.embedded ? FlexFit.loose : FlexFit.tight,
                  child: PayrollUnitItemEditor(
                    embedded: widget.embedded,
                    controller: widget.editorController,
                    showFooter: !widget.externalFooter,
                    section: widget.section,
                    unit: widget.unit,
                    onValidationSelection: widget.onValidationSelection,
                    key: ValueKey(
                      '${widget.companyId}/${widget.workerId}/${_value!.month}/${_value!.version}',
                    ),
                    initialItems: _value!.items,
                    canEdit: _value!.canEdit && !_saving,
                    enableQuantitySources: true,
                    showDailyReportOption: false,
                    onRegister: (items) async {
                      final generation = _generation;
                      final company = widget.companyId;
                      final worker = widget.workerId;
                      final current = _value!;
                      setState(() => _saving = true);
                      try {
                        final saved = await widget.repository.save(
                          company,
                          worker,
                          current,
                          items,
                        );
                        if (!mounted || !context.mounted || generation != _generation ||
                            widget.companyId != company || widget.workerId != worker) {
                          return;
                        }
                        setState(() => _value = saved);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(tr('単位別設定を保存し、対象月の給与を再計算しました')),
                          ),
                        );
                      } finally {
                        if (mounted && generation == _generation) {
                          setState(() => _saving = false);
                        }
                      }
                    },
                  ),
                ),
              ],
            );
    if (widget.embedded) {
      final hasMonthlyItems = _value?.items.any((item) =>
          item.section == widget.section && item.unit == PayrollItemUnit.month) ?? false;
      return Offstage(
        offstage: widget.unit == PayrollItemUnit.month && !_loading &&
            _error == null && !hasMonthlyItems && !(_value?.companyCommonItems.any((item) => item['unit'] == 'month' && item['section'] == widget.section?.name) ?? false),
        child: body,
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('単位別の支給・控除')),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text(tr('単位別の支給・控除')),
                content: SingleChildScrollView(
                  child: Text(
                    tr(
                      '支給・控除ごとに時間・日・月の単価を登録します。時間数は対象月に明示入力するか、登録済みの残業・早出・夜間時間を選びます。日単位は実出勤日数で、同じ日の複数現場は1日です。月単位は月1回で日割りしません。選択した月から条件が有効になり、従来の直接金額は別に保持されます。未入力の時間数は計算保留になります。確定済み給与は変更しません。社内共通手当は会社の設定を自動参照します。共通の時間単位手当は対象月の時間数を入力して保存すると給与を再計算します。会社で適用開始月を設定する前は共通項目を給与に加えません。',
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(tr('閉じる')),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: body,
    );
  }
}

