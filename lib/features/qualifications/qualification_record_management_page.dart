import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'qualification_record_management_repository.dart';

/// Capability remains OFF when the server contract is absent. Registered
/// records and photos are not changed by merely opening this screen.
class QualificationRecordManagementPage extends StatefulWidget {
  const QualificationRecordManagementPage({super.key, required this.companyId,
    required this.targetId, required this.workerName, required this.qualificationName,
    this.delete = false, this.repository});
  final String companyId;
  final String targetId;
  final String workerName;
  final String qualificationName;
  final bool delete;
  final QualificationRecordManagementRepository? repository;
  @override
  State<QualificationRecordManagementPage> createState() => _ChangeState();
}

class _ChangeState extends State<QualificationRecordManagementPage> {
  late final QualificationRecordManagementRepository? _repository;
  final _number = TextEditingController();
  final _issuer = TextEditingController();
  final _issued = TextEditingController();
  final _expires = TextEditingController();
  final _notes = TextEditingController();
  Map<String, dynamic>? _snapshot;
  Map<String, dynamic>? _pending;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  bool _available = false;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? QualificationRecordManagementRepository.maybeCreate();
    _load();
  }

  @override
  void dispose() {
    if (widget.repository == null) _repository?.dispose();
    for (final controller in [_number,_issuer,_issued,_expires,_notes]) {
      controller.dispose();
    }
    super.dispose();
  }

  String _message(Object error) {
    if (error is StateError) return error.message.toString();
    if (error is PostgrestException) {
      return switch(error.code) {
        '40001' => '資格情報が更新されています。内容を再確認してください。',
        '42501' => '現在の権限・ログイン状態を確認してください。',
        '22023' => '入力内容・日付を確認してください。',
        '23505' => '同じ操作番号の内容が一致しません。再送せず管理者へ確認してください。',
        _ => '保存結果を確認できません。同じ保存結果を再確認してください。',
      };
    }
    return '通信結果を確認できません。同じ保存結果を再確認してください。';
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final repository = _repository;
      if (repository == null) throw StateError('SKOへのログインが必要です。');
      final available = await repository.available(widget.companyId);
      final pending = await repository.pending(widget.companyId);
      final snapshot = available && pending == null
        ? await repository.inspect(widget.companyId, widget.targetId) : null;
      if (!mounted) return;
      setState(() {
        _available = available; _pending = pending; _snapshot = snapshot;
        if (snapshot != null) {
          _number.text = snapshot['certificate_number']?.toString() ?? '';
          _issuer.text = snapshot['issuer']?.toString() ?? '';
          _issued.text = snapshot['issued_at']?.toString() ?? '';
          _expires.text = snapshot['expires_at']?.toString() ?? '';
          _notes.text = snapshot['notes']?.toString() ?? '';
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _date(TextEditingController controller) async {
    final today = DateTime.now();
    final picked = await showDatePicker(context: context,
      initialDate: DateTime.tryParse(controller.text) ?? today,
      firstDate: DateTime(1900), lastDate: DateTime(2200));
    if (mounted && picked != null) controller.text = '${picked.year.toString().padLeft(4,'0')}-${picked.month.toString().padLeft(2,'0')}-${picked.day.toString().padLeft(2,'0')}';
  }

  Future<void> _submit() async {
    if (_busy || _snapshot == null) return;
    if (widget.delete) {
      final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
        title: const Text('資格を削除'),
        content: const Text('資格一覧から削除します。元の記録・写真・変更履歴は保持します。'),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('戻る')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('削除'))]));
      if (confirmed != true || !mounted) return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      String? nullable(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
      await _repository!.save(companyId: widget.companyId, snapshot: _snapshot!, targetId: widget.targetId,
        operation: widget.delete ? 'delete' : 'update',
        fields: widget.delete ? null : {'certificate_number': nullable(_number),
          'issuer': nullable(_issuer), 'issued_at': nullable(_issued),
          'expires_at': nullable(_expires), 'notes': nullable(_notes)});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.delete ? '資格を削除しました。' : '資格情報を保存しました。')));
      Navigator.pop(context, true);
    } catch (error) {
      Map<String, dynamic>? pending;
      try { pending = await _repository?.pending(widget.companyId); } catch (_) {}
      if (mounted) setState(() { _error = _message(error); _pending = pending; });
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _recover({bool cancel = false}) async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      final result = cancel ? await _repository!.cancelUncertain(widget.companyId) : await _repository!.recover(widget.companyId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['status']=='applied' ? '同じ資格操作の保存完了を確認しました。' : '未完了の操作を取り消しました。')));
      Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    }
    if (mounted) setState(() => _busy = false);
  }

  Widget _field(String label, TextEditingController controller, {bool date = false, int lines = 1}) =>
    Padding(padding: const EdgeInsets.only(bottom: 12), child: TextField(
      controller: controller, enabled: !_busy, maxLines: lines, readOnly: date,
      onTap: date ? () => _date(controller) : null,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(),
        suffixIcon: date ? IconButton(onPressed: _busy ? null : () => controller.clear(),
          tooltip: '日付を空にする', icon: const Icon(Icons.clear)) : null)));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.delete ? '資格の削除' : '資格情報の編集')),
    body: _loading ? const Center(child: CircularProgressIndicator()) : ListView(
      padding: const EdgeInsets.all(16), children: [
        Text('${widget.workerName}／${widget.qualificationName}', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        if (_error != null) ...[Text(_error!), TextButton(onPressed: _busy ? null : _load, child: const Text('再確認'))],
        if (!_available) const Text('資格情報の編集・削除は準備中です。登録済みの情報と写真は保持しています。'),
        if (_pending != null) ...[
          const Text('保存結果が未確認の資格操作があります。別の操作をせず、同じ保存結果を確認してください。'),
          FilledButton(onPressed: _busy ? null : () => _recover(), child: const Text('同じ保存結果を再確認')),
          TextButton(onPressed: _busy ? null : () => _recover(cancel:true), child: const Text('未完了の操作を取り消す')),
        ] else if (_available && _snapshot != null) ...[
          const Text('① 変更内容を確認'), const SizedBox(height: 12),
          if (!widget.delete) ...[
            _field('証明書番号', _number), _field('発行元', _issuer),
            _field('取得日', _issued, date: true), _field('有効期限', _expires, date: true),
            _field('備考', _notes, lines: 3),
          ] else const Text('この資格を一覧から削除します。写真と履歴は保持します。'),
          const SizedBox(height: 12), const Text('② 内容を確認して保存'),
          const SizedBox(height: 12),
          FilledButton(onPressed: _busy ? null : _submit,
            child: Text(widget.delete ? '資格を削除' : '保存')),
        ],
        if (_busy) const LinearProgressIndicator(),
      ]),
  );
}
