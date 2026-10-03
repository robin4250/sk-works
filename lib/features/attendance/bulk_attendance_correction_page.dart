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
    final proposed = Map<String, dynamic>.from(_proposalFor(entry));
    final site = TextEditingController(
      text: proposed['siteName']?.toString() ?? '',
    );
    final manDays = TextEditingController(
      text: _numberText(proposed['manDays']),
    );
    final overtime = TextEditingController(
      text: _numberText(proposed['overtimeHours']),
    );
    final early = TextEditingController(
      text: _numberText(proposed['earlyHours']),
    );
    final night = TextEditingController(
      text: _numberText(proposed['nightHours']),
    );
    final allowance = TextEditingController(
      text: proposed['allowanceYen']?.toString() ?? '0',
    );
    final notes = TextEditingController(
      text: proposed['notes']?.toString() ?? '',
    );

    final saved = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${entry.date}  ${entry.workerName}'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: site,
                  decoration: const InputDecoration(
                    labelText: '現場',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: manDays,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: '人工',
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: overtime,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: '残業',
                          suffixText: '時間',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: early,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: '早出',
                          suffixText: '時間',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: night,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: '夜勤',
                          suffixText: '時間',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: allowance,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '手当',
                          suffixText: '円',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: notes,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: '備考',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () {
              final parsedManDays = double.tryParse(manDays.text.trim());
              final parsedOvertime = double.tryParse(overtime.text.trim());
              final parsedEarly = double.tryParse(early.text.trim());
              final parsedNight = double.tryParse(night.text.trim());
              final parsedAllowance =
                  int.tryParse(allowance.text.replaceAll(',', '').trim());

              if (site.text.trim().isEmpty ||
                  parsedManDays == null ||
                  parsedManDays < 0 ||
                  parsedOvertime == null ||
                  parsedOvertime < 0 ||
                  parsedEarly == null ||
                  parsedEarly < 0 ||
                  parsedNight == null ||
                  parsedNight < 0 ||
                  parsedAllowance == null) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('入力内容を確認してください')),
                );
                return;
              }

              Navigator.pop(dialogContext, {
                ...entry.snapshot(),
                'siteName': site.text.trim(),
                'manDays': parsedManDays,
                'overtimeHours': parsedOvertime,
                'earlyHours': parsedEarly,
                'nightHours': parsedNight,
                'allowanceYen': parsedAllowance,
                'notes': notes.text.trim(),
              });
            },
            child: const Text('修正内容を保存'),
          ),
        ],
      ),
    );

    site.dispose();
    manDays.dispose();
    overtime.dispose();
    early.dispose();
    night.dispose();
    allowance.dispose();
    notes.dispose();

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
    add('手当', entry.allowanceYen, proposed['allowanceYen']);
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
                    if (count != null && mounted) {
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
