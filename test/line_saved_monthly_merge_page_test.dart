import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/chat/line_import_draft.dart';
import 'package:sk_works/features/chat/line_saved_monthly_merge_page.dart';
import 'package:sk_works/features/chat/line_saved_monthly_merge_repository.dart';

import 'support/line_test_app.dart';

const _target = '11111111-1111-4111-8111-111111111111';
const _source = '22222222-2222-4222-8222-222222222222';

Map<String, dynamic> _sourcePost(String id, String day) => {
  'id': id, 'body': '2026/10/$day\n現場A\n山田',
  'sent_at': '2026-10-${day.padLeft(2, '0')}T09:00:00Z',
  'sender_display_name': '担当者', 'source_type': 'received',
};
Map<String, dynamic> _row(Map<String, dynamic> post, String day) => {
  'row_id': '${post['id']}:worker', 'source_message_id': post['id'],
  'source_fingerprint': lineSourceFingerprint(post),
  'work_date': '2026-10-${day.padLeft(2, '0')}',
  'worker_id': '33333333-3333-4333-8333-333333333333', 'worker_name': '山田',
  'site_id': '44444444-4444-4444-8444-444444444444', 'site_name': '現場A',
  'work_category': 'day', 'man_days': 1, 'overtime_hours': 0,
  'early_hours': 0, 'allowance_names': <String>[],
  'confirmed': true, 'excluded': false, 'manually_edited': true,
};

class _Repository extends Fake implements LineSavedMonthlyMergeRepository {
  bool current = true, loseAck = false, sourceChanged = false, editable = true;
  bool admissionFails = false, sourceCollision = false, alteredConfirmation = false;
  int saves = 0, groupChecks = 0;
  final listeners = <VoidCallback>[];
  Map<String, dynamic>? saved;
  @override bool get isCurrent => current;
  @override void addListener(VoidCallback listener) => listeners.add(listener);
  @override void removeListener(VoidCallback listener) => listeners.remove(listener);
  @override Future<void> close() async {}
  void invalidate() { current = false; for (final listener in [...listeners]) { listener(); } }
  @override Future<List<Map<String, dynamic>>> destinations() async {
    if (admissionFails) { current = false; throw StateError('admission failed before listener'); }
    return [
    {'id': _target, 'name': 'すみだ建設出勤', 'group_type': 'group'},
    {'id': _source, 'name': '過去の保存グループ', 'group_type': 'analysis'},
  ]; }
  @override Future<void> verifyGroups(String target, String source) async {
    groupChecks++;
    expect(target, _target); expect(source, _source);
  }
  @override Future<Map<String, dynamic>> load(String group, DateTime month) async {
    if (group == _target && saved != null) {
      return {
      'revision': 2, 'can_edit': true,
      'features': {'attendance': false, 'invoice': true},
      'source_messages': saved!['p_sources'], 'candidate_rows': saved!['p_rows'],
      'note_comparison': saved!['p_note'],
      'source_kind': saved!['p_source_kind'],
        'confirmed': alteredConfirmation,
      };
    }
    final day = group == _target ? '8' : '1';
    final post = group == _target && sourceCollision
      ? (_sourcePost('saved:$_source:history-1', '1')..['body'] = '保存済みの別原文')
      : _sourcePost(group == _target ? 'received-8' : 'history-1', day);
    return {
      'revision': group == _source && sourceChanged ? 2 : 1,
      'can_edit': editable,
      'features': {'attendance': false, 'invoice': true},
      'source_messages': [post], 'candidate_rows': [_row(post, day)],
      'note_comparison': '手直し済み比較メモ',
      'source_kind': 'received', 'confirmed': false,
    };
  }
  @override Future<Map<String, dynamic>> loadSource(String group, DateTime month) => load(group, month);
  @override Map<String, dynamic> saveCommand({required String groupId,
    required String target, required DateTime month, required int revision,
    required String sourceKind, required List<Map<String, dynamic>> sources,
    required List<Map<String, dynamic>> rows, required String note,
    required bool confirmed}) => jsonDecode(jsonEncode({
      'p_group_id': groupId, 'p_target': target, 'p_month': '2026-10-01',
      'p_expected_revision': revision, 'p_source_kind': sourceKind,
      'p_sources': sources, 'p_rows': rows, 'p_note': note,
      'p_confirmed': confirmed, 'p_command_id': 'same-operation',
    })) as Map<String, dynamic>;
  @override Future<Map<String, dynamic>> save(Map<String, dynamic> command) async {
    saves++; saved = command;
    if (loseAck) throw StateError('response lost after commit');
    return load(_target, DateTime(2026, 10));
  }
}

Future<void> _mount(WidgetTester tester, _Repository repository,
    void Function(bool?) onResult) async {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(LineTestApp(home: Scaffold(body: Builder(builder: (context) =>
    TextButton(onPressed: () async {
      onResult(await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) =>
        LineSavedMonthlyMergePage(groupId: _target, groupName: 'すみだ建設出勤',
          month: DateTime(2026, 10), repository: repository))));
    }, child: const Text('開く'))))));
  await tester.tap(find.text('開く')); await tester.pumpAndSettle();
}

Future<void> _prepare(WidgetTester tester) async {
  await tester.tap(find.byType(DropdownButtonFormField<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.text('過去の保存グループ').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('追加内容を確認')); await tester.pumpAndSettle();
}
Future<void> _save(WidgetTester tester) async {
  await tester.ensureVisible(find.byType(CheckboxListTile));
  await tester.tap(find.byType(CheckboxListTile)); await tester.pump();
  await tester.ensureVisible(find.text('まとめ先へ追加する'));
  await tester.tap(find.text('まとめ先へ追加する')); await tester.pumpAndSettle();
}

void main() {
  testWidgets('select saved group, review dates and append while keeping destination edits', (tester) async {
    final repository = _Repository(); bool? result;
    await _mount(tester, repository, (value) => result = value);
    expect(find.text('まとめ先：すみだ建設出勤'), findsOneWidget);
    await _prepare(tester);
    expect(find.textContaining('2026-10-01、2026-10-08'), findsOneWidget);
    expect(repository.saves, 0);
    await _save(tester);
    expect(result, true); expect(repository.saves, 1);
    expect(repository.groupChecks, 2);
    expect(repository.saved!['p_group_id'], _target);
    expect(repository.saved!['p_note'], '手直し済み比較メモ');
    expect(repository.saved!['p_confirmed'], false);
    final rows = repository.saved!['p_rows'] as List;
    expect(rows, hasLength(2));
    expect(rows.first['manually_edited'], true);
    expect(rows.first['confirmed'], true);
  });

  testWidgets('lost acknowledgement queries saved result without another save', (tester) async {
    final repository = _Repository()..loseAck = true; bool? result;
    await _mount(tester, repository, (value) => result = value);
    await _prepare(tester); await _save(tester);
    expect(result, isNull); expect(repository.saves, 1);
    expect(find.textContaining('保存結果が未確認'), findsOneWidget);
    await tester.ensureVisible(find.text('保存結果を確認'));
    await tester.tap(find.text('保存結果を確認')); await tester.pumpAndSettle();
    expect(result, true); expect(repository.saves, 1);
  });

  testWidgets('changed source requires a fresh preview and never writes', (tester) async {
    final repository = _Repository();
    await _mount(tester, repository, (_) {}); await _prepare(tester);
    repository.sourceChanged = true;
    await _save(tester);
    expect(repository.saves, 0);
    expect(find.textContaining('追加内容をもう一度確認'), findsOneWidget);
  });

  testWidgets('session invalidation clears preview and forbids saving', (tester) async {
    final repository = _Repository();
    await _mount(tester, repository, (_) {}); await _prepare(tester);
    repository.invalidate(); await tester.pumpAndSettle();
    expect(find.textContaining('ログイン状態が変わりました'), findsOneWidget);
    expect(find.text('まとめ先へ追加する'), findsNothing);
    expect(find.text('まとめ先：すみだ建設出勤'), findsNothing);
    expect(repository.saves, 0);
  });

  testWidgets('permission refusal does not expose saved rows or enable save', (tester) async {
    final repository = _Repository()..editable = false;
    await _mount(tester, repository, (_) {}); await _prepare(tester);
    expect(find.textContaining('保存済みデータを取得できません'), findsOneWidget);
    expect(find.text('まとめ先へ追加する'), findsNothing);
    expect(repository.saves, 0);
  });

  testWidgets('initial auth admission failure clears busy state without an auth event', (tester) async {
    final repository = _Repository()..admissionFails = true;
    await _mount(tester, repository, (_) {});
    expect(find.textContaining('ログイン状態が変わりました'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('まとめ先へ追加する'), findsNothing);
  });

  testWidgets('source collision previews both originals and cannot save', (tester) async {
    final repository = _Repository()..sourceCollision = true;
    await _mount(tester, repository, (_) {}); await _prepare(tester);
    await tester.ensureVisible(find.textContaining('追加済み原文が変更されています'));
    await tester.tap(find.textContaining('追加済み原文が変更されています'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(SelectableText, '保存済みの別原文'), findsOneWidget);
    expect(find.widgetWithText(SelectableText, '2026/10/1\n現場A\n山田'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'まとめ先へ追加する'));
    expect(button.onPressed, isNull); expect(repository.saves, 0);
  });

  testWidgets('unknown acknowledgement does not accept another confirmation state', (tester) async {
    final repository = _Repository()..loseAck = true; bool? result;
    await _mount(tester, repository, (value) => result = value);
    await _prepare(tester); await _save(tester);
    repository.alteredConfirmation = true;
    await tester.ensureVisible(find.text('保存結果を確認'));
    await tester.tap(find.text('保存結果を確認')); await tester.pumpAndSettle();
    expect(result, isNull); expect(repository.saves, 1);
    expect(find.textContaining('保存結果を特定できません'), findsOneWidget);
  });
}
