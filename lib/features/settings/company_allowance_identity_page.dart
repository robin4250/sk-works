import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'company_allowance_identity_repository.dart';
import 'company_allowance_identity_helper.dart';

/// Independent staged page; the company-data entry is added by its owner later.
class CompanyAllowanceIdentityPage extends StatefulWidget {
  const CompanyAllowanceIdentityPage({super.key, required this.companyId, this.repository, this.pendingStore});
  final String companyId;
  final CompanyAllowanceIdentityRepository? repository;
  final CompanyAllowanceIdentityPendingStore? pendingStore;
  @override
  State<CompanyAllowanceIdentityPage> createState() => _CompanyAllowanceIdentityPageState();
}

class _CompanyAllowanceIdentityPageState extends State<CompanyAllowanceIdentityPage> {
  late final CompanyAllowanceIdentityRepository _repository;
  late final CompanyAllowanceIdentityPendingStore _store;
  CompanyAllowanceIdentityData? _data;
  CompanyAllowanceIdentityPending? _pending;
  bool _busy = true;
  bool _unavailable = false;
  String? _error;
  List<Map<String, dynamic>> _history = [];
  int? _historyCursor;
  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? SupabaseCompanyAllowanceIdentityRepository();
    _store = widget.pendingStore ?? FileCompanyAllowanceIdentityPendingStore();
    _load();
  }
  @override
  void didUpdateWidget(covariant CompanyAllowanceIdentityPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.companyId != widget.companyId) {
      _data = null;
      _error = '会社が変わりました。この画面を開き直してください。';
    }
  }
  Future<void> _load() async {
    if (mounted) {
      setState(() { _busy = true; _data = null; _error = null; _unavailable = false; });
    }
    try {
      final companyId = widget.companyId;
      final pending = await _store.read(companyId);
      var data = await _repository.read(companyId);
      _store.actorId();
      if (!mounted || widget.companyId != companyId) {
        return;
      }
      if (pending != null) {
        Map<String, dynamic>? committed;
        for (final entry in data.history) {
          if (pending.matches(entry)) {
            committed = entry;
          }
        }
        if (committed == null) {
          final page = await _repository.history(companyId, beforeVersion: pending.expectedVersion + 2, limit: 1);
          _store.actorId();
          for (final entry in page.entries) {
            if (pending.matches(entry)) {
              committed = entry;
            }
          }
        }
        if (committed != null) {
          data = await _repository.read(companyId);
          _store.actorId();
          if (!data.adopted || data.version < pending.expectedVersion + 1) {
            throw const FormatException('最新の保存状態を確認できません');
          }
          await _store.clear(pending);
        }
        if (!mounted || widget.companyId != companyId) {
          return;
        }
        setState(() { _pending = committed == null ? pending : null; });
      } else {
        _pending = null;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _data = data; _unavailable = false; _history = data.history.reversed.toList();
        _historyCursor = data.historyBeforeVersion;
        _error = _pending == null ? null : '先の保存結果が確認できません。再送せず保存状態を再確認してください。';
      });
    } on CompanyAllowanceIdentityUnavailable {
      if (mounted) {
        setState(() { _unavailable = true; _data = null; });
      }
    } catch (_) {
      if (mounted) {
        setState(() { _data = null; _error = '会社手当を読み込めません。権限・接続を確認して再読み込みしてください。'; });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  List<CompanyAllowanceSlot> _target(CompanyAllowanceSlot change) => [
    for (final slot in _data!.slots) slot.slot == change.slot ? change : slot,
  ];
  String _summary(List<CompanyAllowanceSlot> slots) => slots.map((slot) =>
    '${slot.slot}：${slot.active ? slot.name : '未登録'}／${slot.unit}／¥${slot.amountYen}').join('\n');

  Future<void> _write(List<CompanyAllowanceSlot> target, {CompanyAllowanceSlot? change}) async {
    final data = _data;
    if (_busy || _pending != null || data == null || data.companyId != widget.companyId) {
      return;
    }
    final adopted = change == null;
    final accepted = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: Text(adopted ? '会社手当を確認して登録' : (change.active ? '会社手当を保存' : '会社手当を廃止')),
      content: SingleChildScrollView(child: Text('${_summary(target)}\n\n${adopted ? '現在の3枠をそのまま採用します。既存金額・過去給与は変更しません。' : 'この内容で会社の手当設定を保存します。別手当への置換は廃止後に再登録してください。'}')),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('確認して保存'))])) ?? false;
    if (!accepted || !mounted || _busy || _pending != null || !identical(data, _data) || data.companyId != widget.companyId) {
      return;
    }
    setState(() { _busy = true; _error = null; });
    bool sent = false;
    CompanyAllowanceIdentityPending? journal;
    try {
      final stableIds = <String, String>{};
      for (final item in data.items) {
        if (target.firstWhere((s) => s.slot == item['slot']).active) {
          stableIds[item['slot'].toString()] = item['id'] as String;
        }
      }
      final pending = CompanyAllowanceIdentityPending(companyId: data.companyId, actorId: _store.actorId(),
        expectedVersion: data.version, adoption: adopted, slots: target, stableIds: stableIds);
      journal = pending;
      await _store.write(pending);
      _store.actorId();
      if (!mounted || widget.companyId != data.companyId) {
        return;
      }
      setState(() => _pending = pending);
      sent = true;
      final result = change == null ? await _repository.adopt(data.companyId, data.slots) : await _repository.save(data.companyId, data.version, change);
      _store.actorId();
      if (!result.adopted || result.version != pending.expectedVersion + 1 || !result.history.any(pending.matches)) {
        throw const FormatException('保存応答を確認できません');
      }
      await _store.clear(pending);
      if (!mounted || widget.companyId != data.companyId) {
        return;
      }
      setState(() {
        _pending = null; _data = result; _history = result.history.reversed.toList();
        _historyCursor = result.historyBeforeVersion;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('会社手当を保存しました')));
    } catch (error) {
      bool rejected = false;
      if (sent && journal != null && error is PostgrestException && ['40001', '22023', '42501'].contains(error.code)) {
        try {
          _store.actorId();
          await _store.clear(journal);
          _pending = null; rejected = true;
        } catch (_) {
          // Keep the persisted journal if its exact record/actor cannot be cleared.
        }
      }
      if (mounted) {
        setState(() { _data = null; _error = rejected ? '保存は受け付けられませんでした。最新の設定を再確認してください。' : '保存結果を確認できません。再送せず保存状態を再確認してください。'; });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _edit(CompanyAllowanceSlot slot) async {
    if (_busy || _pending != null || _data == null) {
      return;
    }
    final change = await showDialog<CompanyAllowanceSlot>(context: context,
      builder: (_) => _CompanyAllowanceSlotEditor(slot: slot));
    if (change != null && mounted && _data != null) {
      await _write(_target(change), change: change);
    }
  }

  Future<void> _moreHistory() async {
    if (_busy || _historyCursor == null) {
      return;
    }
    setState(() => _busy = true);
    try {
      final companyId = widget.companyId;
      final page = await _repository.history(companyId, beforeVersion: _historyCursor);
      _store.actorId();
      if (mounted && widget.companyId == companyId) {
        setState(() { _history.addAll(page.entries); _historyCursor = page.beforeVersion; });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = '履歴を読み込めません。再読み込みしてください。');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }
  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Scaffold(appBar: AppBar(title: const Text('会社共通手当'), actions: [
      IconButton(tooltip: '会社共通手当の使い方', icon: const Icon(Icons.help_outline), onPressed: () => showDialog<void>(context: context,
        builder: (context) => AlertDialog(title: const Text('会社共通手当の使い方'),
          content: const Text('会社に登録した3枠を一元管理します。改名は同じ手当、廃止後の登録は新しい手当として履歴を残します。保存結果が不明な時は再送せず再確認してください。日報の回数と給与への自動反映はまだ準備中です。'),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('閉じる'))]))),
    ]), body: _busy ? const Center(child: CircularProgressIndicator()) : ListView(padding: const EdgeInsets.all(16), children: [
      if (_unavailable) const Text('会社共通手当は準備中です。既存の会社設定をご利用ください。'),
      if (_error != null) Text(_error!),
      OutlinedButton(onPressed: _load, child: const Text('保存状態を再確認')),
      if (data != null && _pending == null && _error == null) ...[
        if (!data.adopted) ...[
          const Text('登録済みの3枠を確認してから利用を開始します。'),
          Text(_summary(data.slots)),
          FilledButton(onPressed: () => _write(data.slots), child: const Text('登録済み手当を確認')),
        ] else ...[
          for (final slot in data.slots) Card(child: ListTile(title: Text(slot.active ? slot.name! : '未登録'),
            subtitle: Text('単価 ¥${slot.amountYen}／${slot.unit}'),
            trailing: Wrap(children: [TextButton(onPressed: () => _edit(slot), child: Text(slot.active ? '編集' : '登録')),
              if (slot.active) TextButton(onPressed: () {
                final retired = CompanyAllowanceSlot(slot: slot.slot, name: '', unit: slot.unit, amountYen: slot.amountYen);
                _write(_target(retired), change: retired);
              }, child: const Text('廃止'))]))),
        ],
        if (data.adopted) ExpansionTile(title: const Text('変更履歴'), children: [
          for (final entry in _history) ListTile(title: Text('版 ${entry['version']}：${entry['event'] == 'adopt' ? '初回登録' : '設定変更'}'),
            subtitle: Text('${entry['changed_at']}')),
          if (_historyCursor != null) TextButton(onPressed: _moreHistory, child: const Text('前の履歴を表示')),
        ]),
      ],
    ]));
  }
}

class _CompanyAllowanceSlotEditor extends StatefulWidget {
  const _CompanyAllowanceSlotEditor({required this.slot});
  final CompanyAllowanceSlot slot;
  @override
  State<_CompanyAllowanceSlotEditor> createState() => _CompanyAllowanceSlotEditorState();
}
class _CompanyAllowanceSlotEditorState extends State<_CompanyAllowanceSlotEditor> {
  late final TextEditingController _name;
  late final TextEditingController _unit;
  late final TextEditingController _amount;
  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.slot.name ?? '');
    _unit = TextEditingController(text: widget.slot.unit);
    _amount = TextEditingController(text: '${widget.slot.amountYen}');
  }
  @override
  void dispose() {
    _name.dispose(); _unit.dispose(); _amount.dispose(); super.dispose();
  }
  String? get _validation {
    final amount = int.tryParse(_amount.text.trim());
    if (_name.text.trim().isEmpty || _name.text.trim().length > 80 || _unit.text.trim().isEmpty || _unit.text.trim().length > 12 ||
        !RegExp(r'^\d{1,10}$').hasMatch(_amount.text.trim()) || amount == null || amount > 2147483647) {
      return '名称・単位・0以上の金額を入力してください';
    }
    return null;
  }
  @override
  Widget build(BuildContext context) => AlertDialog(title: Text(widget.slot.active ? '手当を編集' : '手当を登録'),
    content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: _name, decoration: const InputDecoration(labelText: '手当名'), onChanged: (_) => setState(() {})),
      TextField(controller: _unit, decoration: const InputDecoration(labelText: '単位'), onChanged: (_) => setState(() {})),
      TextField(controller: _amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '単価（円）'), onChanged: (_) => setState(() {})),
      if (_validation != null) Text(_validation!),
    ])), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
      FilledButton(onPressed: _validation != null ? null : () => Navigator.pop(context,
        CompanyAllowanceSlot(slot: widget.slot.slot, name: _name.text.trim(), unit: _unit.text.trim(), amountYen: int.parse(_amount.text.trim()))), child: const Text('内容を確認'))]);
}
