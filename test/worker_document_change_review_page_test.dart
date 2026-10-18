import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/people/worker_document_change_repository.dart';
import 'package:sk_works/features/people/worker_document_change_review_page.dart';

String id(int n) => '10000000-0000-0000-0000-${n.toString().padLeft(12, '0')}';
const capability = {
  'version': 1,
  'change_requests_available': true,
  'new_upload_available': false,
  'max_photos': 20,
  'self_approval_allowed': false,
};
Map<String, dynamic> raw({bool canReview = true, String status = 'pending'}) =>
    {
      'version': 1,
      'id': id(1),
      'target_id': id(2),
      'company_id': id(3),
      'worker_id': id(4),
      'requirement_id': id(5),
      'requested_by': id(6),
      'status': status,
      'can_review': canReview,
      'previous': {
        'id': id(2),
        'company_id': id(3),
        'worker_id': id(4),
        'requirement_id': id(5),
        'updated_at': '2026-10-18T00:00:00Z',
        'status': 'submitted',
        'original_verified': false,
        'attachment_paths': <String>[],
        'notes': 'old',
        'expires_at': null,
      },
      'proposed': {
        'attachment_paths': <String>[],
        'expires_at': null,
        'notes': 'new',
      },
    };
void main() {
  test(
    'entry rejects malformed prior photo lists/status and proposed new uploads',
    () {
      for (final changes in [
        {
          'attachment_paths': [1],
        },
        {
          'attachment_paths': ['same', 'same'],
        },
        {
          'attachment_paths': [''],
        },
        {'status': 'unknown'},
      ]) {
        final value = raw();
        value['previous'] = {...(value['previous'] as Map), ...changes};
        expect(
          () => WorkerDocumentChangeEntry.parse(value),
          throwsFormatException,
        );
      }
      final value = raw();
      value['proposed'] = {
        'attachment_paths': ['new.pdf'],
        'expires_at': null,
        'notes': 'new',
      };
      expect(
        () => WorkerDocumentChangeEntry.parse(value),
        throwsFormatException,
      );
    },
  );
  testWidgets(
    'read only list identifies worker/document; detail rechecks then explicit approval',
    (tester) async {
      final calls = <String>[];
      final events = StreamController<void>.broadcast(sync: true);
      var status = 'pending';
      final repo = WorkerDocumentChangeRepository.forTesting(
        actor: () => id(7),
        changes: events.stream,
        rpc: (a, d) async {
          calls.add(a);
          if (a == 'capability') return capability;
          if (a == 'list') return [raw(status: status)];
          if (a == 'detail') return raw(status: status);
          if (a == 'approve') {
            status = 'approved';
            return raw(status: status);
          }
          throw StateError(a);
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: WorkerDocumentChangeReviewPage(
            repository: repo,
            companyId: id(3),
            isCurrent: () => true,
            workerNames: {id(4): '社員テスト'},
            requirementNames: {id(5): '履歴書'},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, ['capability', 'list']);
      expect(find.text('社員テスト / 履歴書'), findsOneWidget);
      expect(find.textContaining('承認待ち'), findsOneWidget);
      await tester.tap(find.text('差分を確認'));
      await tester.pumpAndSettle();
      expect(calls.last, 'detail');
      expect(find.text('備考（変更前）：old'), findsOneWidget);
      expect(find.text('備考（変更後）：new'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '承認'));
      await tester.pumpAndSettle();
      expect(calls.where((a) => a == 'approve'), hasLength(1));
      expect(calls.where((a) => a == 'detail'), hasLength(2));
      expect(find.textContaining('承認済み'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await repo.dispose();
        await events.close();
      });
    },
  );
  testWidgets(
    'actor change destroys owned dialog and cannot approve old request',
    (tester) async {
      var actor = id(7);
      final events = StreamController<void>.broadcast(sync: true);
      final calls = <String>[];
      final repo = WorkerDocumentChangeRepository.forTesting(
        actor: () => actor,
        changes: events.stream,
        rpc: (a, d) async {
          calls.add(a);
          return a == 'capability'
              ? capability
              : a == 'list'
              ? [raw()]
              : raw();
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: WorkerDocumentChangeReviewPage(
            repository: repo,
            companyId: id(3),
            isCurrent: () => true,
            workerNames: {id(4): '社員テスト'},
            requirementNames: {id(5): '履歴書'},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('差分を確認'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      actor = id(8);
      events.add(null);
      actor = id(7);
      events.add(null);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.textContaining('old'), findsNothing);
      expect(calls.where((a) => a == 'approve' || a == 'reject'), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await repo.dispose();
        await events.close();
      });
    },
  );
  testWidgets(
    'unknown target names and self/unreviewable requests expose no approval control',
    (tester) async {
      final events = StreamController<void>.broadcast(sync: true);
      final repo = WorkerDocumentChangeRepository.forTesting(
        actor: () => id(7),
        changes: events.stream,
        rpc: (a, d) async => a == 'capability' ? capability : [raw()],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: WorkerDocumentChangeReviewPage(
            repository: repo,
            companyId: id(3),
            isCurrent: () => true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('差分を確認'), findsNothing);
      expect(find.textContaining('対象情報を確認できません'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await repo.dispose();
        await events.close();
      });
    },
  );
  testWidgets('current review denial after confirmation never sends approval', (
    tester,
  ) async {
    var details = 0;
    final calls = <String>[];
    final events = StreamController<void>.broadcast(sync: true);
    final repo = WorkerDocumentChangeRepository.forTesting(
      actor: () => id(7),
      changes: events.stream,
      rpc: (a, d) async {
        calls.add(a);
        if (a == 'capability') return capability;
        if (a == 'list') return [raw()];
        if (a == 'detail') return raw(canReview: ++details == 1);
        throw StateError(a);
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: WorkerDocumentChangeReviewPage(
          repository: repo,
          companyId: id(3),
          isCurrent: () => true,
          workerNames: {id(4): '社員テスト'},
          requirementNames: {id(5): '履歴書'},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('差分を確認'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '承認'));
    await tester.pumpAndSettle();
    expect(calls.where((a) => a == 'approve'), isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await repo.dispose();
      await events.close();
    });
  });
}
