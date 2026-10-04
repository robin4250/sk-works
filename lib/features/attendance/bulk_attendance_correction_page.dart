import 'package:flutter/material.dart';

import '../daily_reports/signature_capture_page.dart';
import 'attendance_correction_repository.dart';
import 'paid_leave_correction_page.dart';

class BulkAttendanceCorrectionPage extends StatefulWidget {
  const BulkAttendanceCorrectionPage({super.key});

  @override
  State<BulkAttendanceCorrectionPage> createState() =>
      _BulkAttendanceCorrectionPageState();
}

class _BulkAttendanceCorrectionPageState
    extends State<BulkAttendanceCorrectionPage> {
  final _repository = AttendanceCorrectionRepository.maybeCreate();

  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  List<AttendanceCorrectionEntry> _entries = const [];
  final Set<String> _selectedIds = {};
  final Map<String, Map<String, dynamic>> _proposedById = {};
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repository = _repository;
    if (repository == null) {
      setState(() {
        _loading = false;
        _error = '過去勤怠の修正を利用できません。';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final entries = await repository.loadMonth(_month);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _selectedIds.removeWhere(
          (id) => !entries.any((entry) => entry.id == id),
        );
        _proposedById.removeWhere(
          (id, _) => !entries.any((entry) => entry.id == id),
        );
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _changeMonth(int delta) async {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
      _selectedIds.clear();
      _proposedById.clear();
    });
    await _load();
  }

  AttendanceCorrectionEntry? _entryById(String id) {
    for (final entry in _entries) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  Map<String, dynamic> _proposalFor(AttendanceCorrectionEntry entry) =>
      _proposedById[entry.id] ?? entry.snapshot();

  bool _isChanged(AttendanceCorrectionEntry entry) {
    final original = entry.snapshot();
    final proposed = _proposalFor(entry);
    for (final key in [
      'siteName',
      'manDays',
      'overtimeHours',
      'earlyHours',
      'nightHours',
      'allowanceYen',
      'allowanceNames',
      'notes',
    ]) {
      if ((original[key]?.toString() ?? '') !=
          (proposed[key]?.toString() ?? '')) {
        return true;
      }
    }
    return false;
  }

  Future<void> _edit(AttendanceCorrectionEntry entry) async {
    final saved = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => _AttendanceCorrectionEditPage(
          entry: entry,
          proposed: Map<String, dynamic>.from(_proposalFor(entry)),
        ),
      ),
    );
    if (saved == null || !mounted) return;
    setState(() {
      _selectedIds.add(entry.id);
      _proposedById[entry.id] = saved;
    });
  }
  Future<void> _submit() async {
    final repository = _repository;
    if (repository == null || _saving) return;

    final selected = [
      for (final id in _selectedIds)
        if (_entryById(id) case final entry?) entry,
    ];

    if (selected.isEmpty) {
      _show('修正対象を1件以上選択してください。');
      return;
    }

    final changed = selected.where(_isChanged).toList();
    if (changed.isEmpty) {
      _show('選択した勤怠に修正内容がありません。');
      return;
    }

    final signature = await Navigator.of(context).push<SignatureResult>(
      MaterialPageRoute(
        builder: (_) => const SignatureCapturePage(),
      ),
    );
    if (signature == null || !mounted) return;

    setState(() => _saving = true);
    try {
      final requestId = await repository.createDraft(
        originals: changed,
        proposedById: _proposedById,
      );
      await repository.submit(
        requestId: requestId,
        signerName: signature.signerName,
        signatureJson: signature.toJson(),
      );

      if (!mounted) return;
      Navigator.of(context).pop(changed.length);
    } catch (error) {
      if (!mounted) return;
      _show('まとめて修正申請できませんでした: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _show(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _summary(AttendanceCorrectionEntry entry) {
    final proposed = _proposalFor(entry);
    final changes = <String>[];

    void add(String label, Object? before, Object? after) {
      if ((before?.toString() ?? '') != (after?.toString() ?? '')) {
        changes.add('$label ${before ?? ''}→${after ?? ''}');
      }
    }

    add('現場', entry.siteName, proposed['siteName']);
    add('人工', _numberText(entry.manDays), _numberText(proposed['manDays']));
    add(
      '残業',
      _numberText(entry.overtimeHours),
      _numberText(proposed['overtimeHours']),
    );
    add(
      '早出',
      _numberText(entry.earlyHours),
      _numberText(proposed['earlyHours']),
    );
    add(
      '夜勤',
      _numberText(entry.nightHours),
      _numberText(proposed['nightHours']),
    );
    add('手当', entry.allowanceNames.join('・'), ((proposed['allowanceNames'] as List<dynamic>? ?? const []).join('・')));
    add('備考', entry.notes, proposed['notes']);

    return changes.isEmpty ? 'タップして修正内容を入力' : changes.join(' / ');
  }

  static String _numberText(Object? value) {
    final number = (value as num?)?.toDouble() ??
        double.tryParse(value?.toString() ?? '') ??
        0;
    if (number == number.roundToDouble()) return number.toInt().toString();
    return number
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  @override
  Widget build(BuildContext context) {
    final selectedChanged = _entries
        .where((entry) => _selectedIds.contains(entry.id) && _isChanged(entry))
        .length;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '勤務修正',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          TextButton(
            onPressed: _saving
                ? null
                : () async {
                    final count = await Navigator.of(context).push<int>(
                      MaterialPageRoute(
                        builder: (_) => const PaidLeaveCorrectionPage(),
                      ),
                    );
                    if (count != null && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('$count日の有給勤務修正を申請しました')),
                      );
                    }
                  },
            child: const Text('休み→有給'),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: FilledButton.icon(
          onPressed: _loading || _saving ? null : _submit,
          icon: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.draw_outlined),
          label: Text(
            _saving
                ? '申請中…'
                : '最後に1回だけおまとめサイン（$selectedChanged件）',
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
              child: Row(
                children: [
                  IconButton(
                    tooltip: '前の月',
                    onPressed: _loading ? null : () => _changeMonth(-1),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Text(
                      '${_month.year}年${_month.month}月',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ),
                  IconButton(
                    tooltip: '次の月',
                    onPressed: _loading ? null : () => _changeMonth(1),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(_error!, textAlign: TextAlign.center),
                                const SizedBox(height: 16),
                                FilledButton.icon(
                                  onPressed: _load,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('再読み込み'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : _entries.isEmpty
                          ? const Center(
                              child: Text('この月の勤怠データはありません'),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(
                                12,
                                10,
                                12,
                                24,
                              ),
                              itemCount: _entries.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 6),
                              itemBuilder: (context, index) {
                                final entry = _entries[index];
                                final selected =
                                    _selectedIds.contains(entry.id);
                                final changed = _isChanged(entry);

                                return Card(
                                  child: CheckboxListTile(
                                    value: selected,
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                    title: Text(
                                      '${entry.date}  ${entry.workerName}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(entry.siteName),
                                        const SizedBox(height: 3),
                                        Text(
                                          _summary(entry),
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: changed
                                                ? FontWeight.w800
                                                : FontWeight.normal,
                                            color: changed
                                                ? Theme.of(context)
                                                    .colorScheme
                                                    .primary
                                                : null,
                                          ),
                                        ),
                                      ],
                                    ),
                                    secondary: IconButton(
                                      tooltip: '修正内容を入力',
                                      onPressed: () => _edit(entry),
                                      icon: const Icon(Icons.edit_outlined),
                                    ),
                                    onChanged: (value) {
                                      setState(() {
                                        if (value == true) {
                                          _selectedIds.add(entry.id);
                                        } else {
                                          _selectedIds.remove(entry.id);
                                        }
                                      });
                                    },
                                  ),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttendanceCorrectionEditPage extends StatefulWidget {
  const _AttendanceCorrectionEditPage({
    required this.entry,
    required this.proposed,
  });

  final AttendanceCorrectionEntry entry;
  final Map<String, dynamic> proposed;

  @override
  State<_AttendanceCorrectionEditPage> createState() =>
      _AttendanceCorrectionEditPageState();
}

class _AttendanceCorrectionEditPageState
    extends State<_AttendanceCorrectionEditPage> {
  late final TextEditingController _site;
  late final TextEditingController _manDays;
  late final TextEditingController _overtime;
  late final TextEditingController _early;
  late final TextEditingController _night;
  late final TextEditingController _notes;
  final List<TextEditingController> _allowances = [];

  @override
  void initState() {
    super.initState();
    final proposed = widget.proposed;
    _site = TextEditingController(text: proposed['siteName']?.toString() ?? '');
    _manDays = TextEditingController(text: _numberText(proposed['manDays']));
    _overtime = TextEditingController(text: _numberText(proposed['overtimeHours']));
    _early = TextEditingController(text: _numberText(proposed['earlyHours']));
    _night = TextEditingController(text: _numberText(proposed['nightHours']));
    _notes = TextEditingController(text: proposed['notes']?.toString() ?? '');
    for (final value in (proposed['allowanceNames'] as List<dynamic>? ?? const [])) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) _allowances.add(TextEditingController(text: text));
    }
  }

  @override
  void dispose() {
    _site.dispose();
    _manDays.dispose();
    _overtime.dispose();
    _early.dispose();
    _night.dispose();
    _notes.dispose();
    for (final controller in _allowances) {
      controller.dispose();
    }
    super.dispose();
  }

  void _save() {
    final parsedManDays = double.tryParse(_manDays.text.trim());
    final parsedOvertime = double.tryParse(_overtime.text.trim());
    final parsedEarly = double.tryParse(_early.text.trim());
    final parsedNight = double.tryParse(_night.text.trim());
    if (_site.text.trim().isEmpty ||
        parsedManDays == null || parsedManDays < 0 ||
        parsedOvertime == null || parsedOvertime < 0 ||
        parsedEarly == null || parsedEarly < 0 ||
        parsedNight == null || parsedNight < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('入力内容を確認してください')),
      );
      return;
    }
    final allowanceNames = [
      for (final controller in _allowances)
        if (controller.text.trim().isNotEmpty) controller.text.trim(),
    ];
    Navigator.of(context).pop<Map<String, dynamic>>({
      ...widget.entry.snapshot(),
      'siteName': _site.text.trim(),
      'manDays': parsedManDays,
      'overtimeHours': parsedOvertime,
      'earlyHours': parsedEarly,
      'nightHours': parsedNight,
      'allowanceYen': 0,
      'allowanceNames': allowanceNames,
      'notes': _notes.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('勤務修正入力', style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save_outlined),
          label: const Text('修正内容を保存'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        ),
      ),
      body: SafeArea(
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            16, 12, 16, MediaQuery.viewInsetsOf(context).bottom + 28,
          ),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.entry.date, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                    const SizedBox(height: 4),
                    Text(widget.entry.workerName, style: const TextStyle(fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _site,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: '現場',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 16),
              ),
            ),
            const SizedBox(height: 12),
            _numberField(_manDays, '人工'),
            const SizedBox(height: 12),
            _numberField(_overtime, '残業', suffix: '時間'),
            const SizedBox(height: 12),
            _numberField(_early, '早出', suffix: '時間'),
            const SizedBox(height: 12),
            _numberField(_night, '夜勤', suffix: '時間'),
            const SizedBox(height: 16),
            Row(
              children: [
                const Expanded(
                  child: Text('手当', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => setState(() => _allowances.add(TextEditingController())),
                  icon: const Icon(Icons.add),
                  label: const Text('手当を追加'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_allowances.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('手当なし'),
              )
            else
              for (var i = 0; i < _allowances.length; i++) ...[
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _allowances[i],
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: '手当${i + 1}',
                          hintText: '例：PC、職長、夜間作業',
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: 'この手当を削除',
                      onPressed: () => setState(() => _allowances.removeAt(i).dispose()),
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
            const SizedBox(height: 6),
            TextField(
              controller: _notes,
              minLines: 3,
              maxLines: 6,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                labelText: '備考',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.all(14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _numberField(
    TextEditingController controller,
    String label, {
    String? suffix,
  }) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      ),
    );
  }

  static String _numberText(Object? value) {
    final number = (value as num?)?.toDouble() ??
        double.tryParse(value?.toString() ?? '') ??
        0;
    if (number == number.roundToDouble()) return number.toInt().toString();
    return number.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
}
