import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sk_works/features/people/worker_document_change_flow.dart';
import 'package:sk_works/features/people/worker_document_change_repository.dart';

String id(int n) => '10000000-0000-0000-0000-${n.toString().padLeft(12, '0')}';
WorkerDocumentChangeCommand command({String? notes = 'draft'}) =>
    WorkerDocumentChangeCommand(
      requestId: id(1),
      targetId: id(2),
      companyId: id(3),
      workerId: id(4),
      requirementId: id(5),
      requestedBy: id(6),
      expectedUpdatedAt: '2026-10-18T00:00:00Z',
      paths: const [],
      expiresAt: null,
      notes: notes,
    );
Map<String, dynamic> receipt(WorkerDocumentChangeCommand c, String status) => {
  'version': 1,
  'id': c.requestId,
  'target_id': c.targetId,
  'company_id': c.companyId,
  'worker_id': c.workerId,
  'requirement_id': c.requirementId,
  'requested_by': c.requestedBy,
  'status': status,
  'can_review': false,
  'previous': {
    'id': c.targetId,
    'company_id': c.companyId,
    'worker_id': c.workerId,
    'requirement_id': c.requirementId,
    'updated_at': c.expectedUpdatedAt,
  },
  'proposed': c.proposed,
};
const capability = {
  'version': 1,
  'change_requests_available': true,
  'new_upload_available': false,
  'max_photos': 20,
  'self_approval_allowed': false,
};
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'durable fixed command round trip, actor isolation and replacement refusal',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final store = WorkerDocumentChangeStore(prefs);
      final c = command();
      await store.write(c);
      expect(
        WorkerDocumentChangeStore(
          prefs,
        ).read(c.requestedBy, c.targetId)!.preparePayload,
        c.preparePayload,
      );
      expect(store.read(id(9), c.targetId), isNull);
      await expectLater(
        store.write(command(notes: 'changed')),
        throwsStateError,
      );
      expect(store.read(c.requestedBy, c.targetId)!.notes, 'draft');
      await store.clear(c);
      expect(store.read(c.requestedBy, c.targetId), isNull);
    },
  );
  test(
    'registration policy distinguishes empty placeholders from saved metadata',
    () {
      expect(workerDocumentHasRegisteredContent(null), false);
      expect(workerDocumentHasRegisteredContent({'status': 'missing'}), false);
      for (final row in [
        {'status': 'submitted'},
        {'status': 'not_submitted', 'notes': 'saved'},
        {'status': 'missing', 'expires_at': '2027-01-01'},
        {'status': 'missing', 'attachment_path': 'saved'},
      ]) {
        expect(workerDocumentHasRegisteredContent(row), true);
      }
    },
  );
  testWidgets(
    'lost submit response survives reopen and uses same ID without duplicate submit',
    (tester) async {
      final c = command();
      final store = (await tester.runAsync(() async {
        final store = WorkerDocumentChangeStore(
          await SharedPreferences.getInstance(),
        );
        await store.write(c);
        return store;
      }))!;
      final calls = <String>[];
      var submitted = false;
      final events = StreamController<void>.broadcast(sync: true);
      final repo = WorkerDocumentChangeRepository.forTesting(
        actor: () => c.requestedBy,
        changes: events.stream,
        rpc: (a, d) async {
          calls.add(a);
          if (a == 'capability') return capability;
          expect(d['request_id'], c.requestId);
          if (a == 'prepare') {
            return receipt(c, submitted ? 'pending' : 'draft');
          }
          if (a == 'submit') {
            submitted = true;
            throw StateError('response lost');
          }
          throw StateError('unexpected write');
        },
      );
      Widget page() => MaterialApp(
        home: WorkerDocumentChangePage(
          repository: repo,
          actor: c.requestedBy,
          companyId: c.companyId,
          row: {
            'id': c.targetId,
            'worker_id': c.workerId,
            'requirement_id': c.requirementId,
            'updated_at': c.expectedUpdatedAt,
          },
          signedUrl: (_) async => 'unused',
          isCurrent: () => true,
        ),
      );
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      await tester.tap(find.text('前の申請の結果を確認'));
      await tester.pumpAndSettle();
      expect(store.read(c.requestedBy, c.targetId), isNotNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      await tester.tap(find.text('前の申請の結果を確認'));
      await tester.pumpAndSettle();
      expect(calls.where((a) => a == 'submit'), hasLength(1));
      expect(calls.where((a) => a == 'prepare'), hasLength(2));
      expect(store.read(c.requestedBy, c.targetId), isNull);
      expect(find.textContaining('承認されるまで正式な書類は変わりません'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await repo.dispose();
        await events.close();
      });
    },
  );
  testWidgets(
    'missing capability disables submission and actor transition destroys draft UI',
    (tester) async {
      var actor = id(6);
      final events = StreamController<void>.broadcast(sync: true);
      final calls = <String>[];
      final repo = WorkerDocumentChangeRepository.forTesting(
        actor: () => actor,
        changes: events.stream,
        rpc: (a, d) async {
          calls.add(a);
          return {...capability, 'change_requests_available': false};
        },
      );
      final c = command();
      await tester.pumpWidget(
        MaterialApp(
          home: WorkerDocumentChangePage(
            repository: repo,
            actor: actor,
            companyId: c.companyId,
            row: {'id': c.targetId, 'notes': 'private old notes'},
            signedUrl: (_) async => 'unused',
            isCurrent: () => true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('準備中です。正式な書類は変更していません'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      actor = id(7);
      events.add(null);
      await tester.pump();
      expect(find.byType(TextField), findsNothing);
      expect(calls, ['capability']);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await repo.dispose();
        await events.close();
      });
    },
  );
  testWidgets(
    'saved photo removal sends approval proposal and leaves official map unchanged',
    (tester) async {
      final c = command(notes: null);
      final events = StreamController<void>.broadcast(sync: true);
      final calls = <String>[];
      WorkerDocumentChangeCommand? sent;
      final repo = WorkerDocumentChangeRepository.forTesting(
        actor: () => c.requestedBy,
        changes: events.stream,
        rpc: (a, d) async {
          calls.add(a);
          if (a == 'capability') return capability;
          if (a == 'prepare') {
            sent = decodeWorkerDocumentChangeCommand({
              ...d,
              'company_id': c.companyId,
              'worker_id': c.workerId,
              'requirement_id': c.requirementId,
              'requested_by': c.requestedBy,
            });
            return receipt(sent!, 'draft');
          }
          return receipt(sent!, 'pending');
        },
      );
      final row = {
        'id': c.targetId,
        'worker_id': c.workerId,
        'requirement_id': c.requirementId,
        'updated_at': c.expectedUpdatedAt,
        'attachment_paths': ['front.pdf', 'back.pdf'],
        'status': 'submitted',
      };
      await tester.pumpWidget(
        MaterialApp(
          home: WorkerDocumentChangePage(
            repository: repo,
            actor: c.requestedBy,
            companyId: c.companyId,
            row: row,
            signedUrl: (p) async => 'https://example.invalid/$p',
            isCurrent: () => true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存済み写真（2枚）'));
      await tester.pumpAndSettle();
      for (final button in tester.widgetList<OutlinedButton>(
        find.widgetWithText(OutlinedButton, '1枚撮影'),
      )) {
        expect(button.onPressed, isNull);
      }
      await tester.tap(find.byTooltip('写真を一覧から削除').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('写真を確定'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('変更を申請'));
      await tester.pumpAndSettle();
      expect(sent!.paths, ['front.pdf']);
      expect(calls, ['capability', 'prepare', 'submit']);
      expect(row['attachment_paths'], ['front.pdf', 'back.pdf']);
      expect(find.textContaining('承認されるまで正式な書類は変わりません'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await repo.dispose();
        await events.close();
      });
    },
  );
  testWidgets(
    'persisted command with changed company scope is rejected before RPC',
    (tester) async {
      final c = command();
      await tester.runAsync(() async {
        await WorkerDocumentChangeStore(
          await SharedPreferences.getInstance(),
        ).write(c);
      });
      final events = StreamController<void>.broadcast(sync: true);
      final calls = <String>[];
      final repo = WorkerDocumentChangeRepository.forTesting(
        actor: () => c.requestedBy,
        changes: events.stream,
        rpc: (a, d) async {
          calls.add(a);
          return capability;
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: WorkerDocumentChangePage(
            repository: repo,
            actor: c.requestedBy,
            companyId: id(99),
            row: {
              'id': c.targetId,
              'worker_id': c.workerId,
              'requirement_id': c.requirementId,
            },
            signedUrl: (_) async => 'unused',
            isCurrent: () => true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      expect(find.text('申請を確認できません。画面を開き直してください。'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await repo.dispose();
        await events.close();
      });
    },
  );
  testWidgets('background destroys photo modal and hides private draft', (
    tester,
  ) async {
    final c = command();
    final events = StreamController<void>.broadcast(sync: true);
    final repo = WorkerDocumentChangeRepository.forTesting(
      actor: () => c.requestedBy,
      changes: events.stream,
      rpc: (a, d) async => capability,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: WorkerDocumentChangePage(
          repository: repo,
          actor: c.requestedBy,
          companyId: c.companyId,
          row: {'id': c.targetId, 'notes': 'private'},
          signedUrl: (_) async => 'unused',
          isCurrent: () => true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存済み写真（0枚）'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(tester.takeException(), isNull);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.byType(TextField), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await repo.dispose();
      await events.close();
    });
  });
}
