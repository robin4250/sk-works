import 'package:flutter/material.dart';
import 'shift_day_editor.dart';
import 'shift_draft_request.dart';
import 'shift_people_picker.dart';

/// Client-only editor. The injected save must perform server-side permission,
/// company/site ownership and expected-revision checks in one transaction.
class ShiftScheduleEditor extends StatefulWidget {
  const ShiftScheduleEditor({super.key, required this.companyId,
    required this.date, required this.people, required this.sites,
    required this.initial, required this.revisions, required this.save, this.publish});
  final String companyId;
  final DateTime date;
  final List<ShiftPersonOption> people;
  final List<ShiftSiteOption> sites;
  final ShiftDayDraft initial;
  final Map<String, int> revisions;
  final Future<void> Function(List<ShiftDraftRequest>) save;
  /// The server rechecks manager permission, revision and rollout atomically.
  final Future<void> Function(List<ShiftDraftRequest>)? publish;

  @override
  State<ShiftScheduleEditor> createState() => _ShiftScheduleEditorState();
}

class _ShiftScheduleEditorState extends State<ShiftScheduleEditor> {
  late ShiftDayDraft draft = widget.initial;
  late Map<String, int> revisions = Map.of(widget.revisions);
  Set<String> selected = {};
  bool saving = false;
  String? message;
  List<ShiftDraftRequest>? savedForPublication;

  Future<void> submit() async {
    if (saving) return;
    final available = widget.people.map((e) => e.id).toSet();
    if (selected.isEmpty || !available.containsAll(selected)) {
      setState(() => message = '従業員を選択してください。');
      return;
    }
    final requests = [for (final id in selected) ShiftDraftRequest(
      companyId: widget.companyId, workerId: id, siteId: draft.siteId,
      workDate: widget.date, holiday: draft.holiday, night: draft.night,
      startMinute: draft.start.hour * 60 + draft.start.minute,
      endMinute: draft.end.hour * 60 + draft.end.minute,
      checkLate: draft.checkLate, checkEarly: draft.checkEarly,
      revision: revisions[id] ?? 0)];
    final invalidSite = !draft.holiday && !widget.sites.any((s) => s.id == draft.siteId);
    final problem = invalidSite ? '出勤先を選択してください。' : requests.first.validate();
    if (problem != null) {
      setState(() => message = problem);
      return;
    }
    setState(() { saving = true; message = null; });
    try {
      await widget.save(List.unmodifiable(requests));
      if (mounted) {
        setState(() {
        for (final request in requests) {
          revisions[request.workerId] = request.revision + 1;
        }
        savedForPublication = [for (final request in requests) ShiftDraftRequest(
          companyId: request.companyId, workerId: request.workerId, siteId: request.siteId,
          workDate: request.workDate, holiday: request.holiday, night: request.night,
          startMinute: request.startMinute, endMinute: request.endMinute,
          checkLate: request.checkLate, checkEarly: request.checkEarly,
          revision: request.revision + 1)];
        message = '下書きを保存しました。';
        });
      }
    } catch (_) {
      if (mounted) setState(() => message = '保存結果を確認できません。再読み込みして確認してください。');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> publishSaved() async {
    final rows = savedForPublication;
    if (saving || rows == null || widget.publish == null) return;
    setState(() { saving = true; message = null; });
    try {
      await widget.publish!(List.unmodifiable(rows));
      if (mounted) setState(() { savedForPublication = null; message = 'シフトを確定しました。'; });
    } catch (_) {
      if (mounted) setState(() => message = '確定結果を確認できません。再読み込みしてください。');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('シフトの下書き')),
    body: SingleChildScrollView(child: Column(children: [
      Text('${widget.date.year}年${widget.date.month}月${widget.date.day}日'),
      ShiftPeoplePicker(people: widget.people, selectedIds: selected,
        onChanged: saving ? (_) {} : (ids) => setState(() { selected = ids; savedForPublication = null; })),
      ShiftDayEditor(value: draft, sites: widget.sites,
        onChanged: saving ? (_) {} : (value) => setState(() { draft = value; savedForPublication = null; })),
      if (message != null) Text(message!),
      FilledButton(onPressed: saving ? null : submit, child: const Text('下書きを保存')),
      if (widget.publish != null)
        FilledButton(onPressed: saving || savedForPublication == null ? null : publishSaved,
          child: const Text('保存したシフトを確定')),
    ])),
  );
}
