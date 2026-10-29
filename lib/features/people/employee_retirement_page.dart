import 'package:flutter/material.dart';

import 'employee_retirement_repository.dart';

class EmployeeRetirementPage extends StatefulWidget {
  const EmployeeRetirementPage({super.key, required this.companyId,
    required this.workerId, required this.workerName, this.repository});
  final String companyId, workerId, workerName;
  @visibleForTesting final EmployeeRetirementRepository? repository;
  @override State<EmployeeRetirementPage> createState() => _EmployeeRetirementPageState();
}

class _EmployeeRetirementPageState extends State<EmployeeRetirementPage> {
  bool _confirmed = false, _busy = false;
  String? _error;

  Future<void> _submit() async {
    if (_busy || !_confirmed) return;
    final repository = widget.repository ?? EmployeeRetirementRepository.maybeCreate();
    if (repository == null) {
      setState(() => _error = 'ログイン情報を確認できません。画面を開き直してください。');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await repository.retire(companyId: widget.companyId,
        workerId: widget.workerId);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) setState(() => _error =
        '退職処理を確認できません。一覧を再読み込みして状態を確認してください。再実行は自動で行いません。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('退職手続き')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text(widget.workerName, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        const Text('退職後は退職者一覧に表示します。社員情報・給与・日報・署名・資格書類は削除しません。'),
        CheckboxListTile(value: _confirmed, title: const Text('対象を確認し、退職として登録します'),
          onChanged: _busy ? null : (value) => setState(() => _confirmed = value == true)),
        if (_error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(_error!)),
        const SizedBox(height: 20),
        FilledButton(onPressed: !_busy && _confirmed ? _submit : null,
          child: Text(_busy ? '確認しています…' : '退職として登録')),
      ]),
    ),
  );
}
