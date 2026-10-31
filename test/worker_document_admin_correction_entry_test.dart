import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/people/worker_document_admin_correction_entry.dart';
import 'package:sk_works/features/people/worker_document_admin_correction_repository.dart';

void main() {
  const actor = '70000000-0000-0000-0000-000000000004';
  const company = '70000000-0000-0000-0000-000000000001';
  const target = '70000000-0000-0000-0000-000000000006';
  final snapshot = <String, dynamic>{
    'id': target,
    'company_id': company,
    'worker_id': 'own-worker',
    'requirement_id': 'own-requirement',
    'status': 'submitted',
    'attachment_paths': <String>[],
    'expires_at': null,
    'notes': null,
  };
  final inspected = <String, dynamic>{
    ...snapshot,
    'updated_by': actor,
    'template_version_id': null,
    'updated_at': '2026-10-31T00:00:00+00:00',
  };
  Map<String, dynamic> capability(bool available) => {
    'version': 1,
    'contract': 'worker_document_admin_self_correction',
    'company_id': company,
    'target_id': target,
    'actor_id': actor,
    'available': available,
    'new_upload_available': false,
    'max_photos': 20,
  };
  late SharedPreferences preferences;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
  });
  Future<void> host(
    WidgetTester tester,
    Future<Object?> Function(String, Map<String, dynamic>) rpc,
    void Function(bool) completed, {
    bool Function()? current,
    void Function(Object)? onError,
  }) async {
    final repository = WorkerDocumentAdminCorrectionRepository.forTesting(
      actor: actor,
      companyId: company,
      targetId: target,
      preferences: preferences,
      rpc: rpc,
      requireCurrent: () {},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                try {
                  completed(
                    await openWorkerDocumentAdminCorrection(
                      context: context,
                      repository: repository,
                      snapshot: snapshot,
                      documentName: '健康診断書',
                      isCurrentTarget: current ?? () => true,
                    ),
                  );
                } catch (error) {
                  onError?.call(error);
                }
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('OFF capability preserves ordinary employee request route', (
    tester,
  ) async {
    bool? handled;
    await host(
      tester,
      (action, data) async => capability(false),
      (value) => handled = value,
    );
    expect(handled, false);
    expect(find.text('本人書類の管理訂正'), findsNothing);
  });
  testWidgets(
    'missing endpoint and ordinary employee denial preserve old route',
    (tester) async {
      for (final denied in const [
        [
          'PGRST202',
          'Could not find the function public.worker_document_admin_self_correction(p_action, p_data) in the schema cache',
        ],
        ['42501', 'administrator required'],
        ['42501', 'people permission required'],
        ['42501', 'own active worker required'],
      ]) {
        bool? handled;
        await host(
          tester,
          (action, data) async =>
              throw PostgrestException(message: denied[1], code: denied[0]),
          (value) => handled = value,
        );
        expect(handled, false);
      }
    },
  );
  testWidgets(
    'malformed and foreign capabilities never fall back to an old write route',
    (tester) async {
      for (final raw in [
        null,
        {...capability(true), 'company_id': 'other-company'},
        {...capability(true), 'actor_id': 'other-actor'},
        {...capability(true), 'target_id': 'other-target'},
        {...capability(true), 'contract': 'other-purpose'},
        {...capability(true), 'available': 'false'},
        {...capability(true), 'version': 1.0},
        {...capability(true), 'extra': true},
      ]) {
        Object? error;
        await host(
          tester,
          (action, data) async => raw,
          (_) => fail('must not adopt'),
          onError: (value) => error = value,
        );
        expect(error, isFormatException);
      }
    },
  );
  testWidgets(
    'unknown auth SID ACL and helper failures stop instead of falling back',
    (tester) async {
      for (final denied in const [
        ['42501', 'reauthentication_required'],
        [
          '42501',
          'permission denied for function worker_document_admin_self_correction',
        ],
        ['42501', 'unknown permission failure'],
        ['42883', 'function private.unknown_helper() does not exist'],
        [
          'PGRST202',
          'Could not find the function public.other_function(p_action, p_data) in the schema cache',
        ],
      ]) {
        Object? error;
        await host(
          tester,
          (action, data) async =>
              throw PostgrestException(message: denied[1], code: denied[0]),
          (_) => fail('must not adopt'),
          onError: (value) => error = value,
        );
        expect(error, isA<PostgrestException>());
      }
    },
  );
  testWidgets(
    'unknown failures and retired target do not silently switch routes',
    (tester) async {
      Object? error;
      await host(
        tester,
        (action, data) async => throw StateError('retired'),
        (_) => fail('must not adopt'),
        onError: (value) => error = value,
      );
      expect(error, isStateError);
      error = null;
      await host(
        tester,
        (action, data) async => capability(true),
        (_) => fail('must not adopt'),
        current: () => false,
        onError: (value) => error = value,
      );
      expect(error, isStateError);
    },
  );
  testWidgets(
    'pending operation stays recovery-only while feature OFF after restart',
    (tester) async {
      const request = '70000000-0000-0000-0000-000000000020';
      await preferences.setString(
        'sko.document.admin.correction.v1:$actor:$company:$target',
        '{"version":1,"actor_id":"$actor","company_id":"$company","target_id":"$target","request_id":"$request"}',
      );
      bool? handled;
      await host(tester, (action, data) async {
        expect(action, 'reconcile_cancel');
        return {
          'version': 1,
          'contract': 'worker_document_admin_self_correction',
          'request_id': request,
          'company_id': company,
          'target_id': target,
          'actor_id': actor,
          'status': 'applied',
        };
      }, (value) => handled = value);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('変更を保存'), findsNothing);
      expect(handled, isNull);
      await tester.tap(find.text('前の変更結果を確認'));
      await tester.pumpAndSettle();
      expect(handled, true);
      expect(preferences.getKeys(), isEmpty);
    },
  );
  testWidgets(
    'scoped journal recovery is reachable without original status row',
    (tester) async {
      const request = '70000000-0000-0000-0000-000000000020';
      await preferences.setString(
        'sko.document.admin.correction.v1:$actor:$company:$target',
        '{"version":1,"actor_id":"$actor","company_id":"$company","target_id":"$target","request_id":"$request"}',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => recoverPendingWorkerDocumentAdminCorrections(
                  context: context,
                  isCurrent: () => true,
                  pendingTargets: () async =>
                      WorkerDocumentAdminCorrectionRepository.pendingTargets(
                        preferences,
                        actor,
                        company,
                      ),
                  createRepository: (target) async =>
                      WorkerDocumentAdminCorrectionRepository.forTesting(
                        actor: actor,
                        companyId: company,
                        targetId: target,
                        preferences: preferences,
                        requireCurrent: () {},
                        rpc: (action, data) async {
                          expect(action, 'reconcile_cancel');
                          return {
                            'version': 1,
                            'contract': 'worker_document_admin_self_correction',
                            'request_id': request,
                            'company_id': company,
                            'target_id': target,
                            'actor_id': actor,
                            'status': 'cancelled',
                          };
                        },
                      ),
                ),
                child: const Text('recover'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('recover'));
      await tester.pumpAndSettle();
      expect(find.text('未確認の書類訂正'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.text('前の変更結果を確認'));
      await tester.pumpAndSettle();
      expect(preferences.getKeys(), isEmpty);
    },
  );
  testWidgets(
    'exact capability opens distinct correction and expiry/reason save keeps snapshot',
    (tester) async {
      bool? handled;
      Map<String, dynamic>? saved;
      await host(tester, (action, data) async {
        if (action == 'capability') {
          return capability(true);
        }
        if (action == 'inspect') {
          return {
            'version': 1,
            'contract': 'worker_document_admin_self_correction',
            'company_id': company,
            'target_id': target,
            'actor_id': actor,
            'snapshot': inspected,
          };
        }
        expect(action, 'correct');
        saved = data;
        return {
          'version': 1,
          'contract': 'worker_document_admin_self_correction',
          'request_id': data['request_id'],
          'company_id': company,
          'target_id': target,
          'actor_id': actor,
          'status': 'applied',
        };
      }, (value) => handled = value);
      expect(find.text('本人書類の管理訂正'), findsOneWidget);
      expect(find.text('健康診断書'), findsOneWidget);
      await tester.enterText(find.byType(TextField).at(0), '2030-01-01');
      await tester.enterText(find.byType(TextField).at(2), '期限の入力漏れを訂正');
      await tester.ensureVisible(find.text('変更を保存'));
      await tester.tap(find.text('変更を保存'));
      await tester.pumpAndSettle();
      expect(find.text('本人の書類を管理訂正'), findsOneWidget);
      await tester.tap(find.text('変更を保存').last);
      await tester.pumpAndSettle();
      expect(handled, true);
      expect(saved?['expected_snapshot'], inspected);
      expect((saved?['fields'] as Map)['expires_at'], '2030-01-01');
      expect(saved?['reason'], '期限の入力漏れを訂正');
      expect(preferences.getKeys(), isEmpty);
    },
  );
}
