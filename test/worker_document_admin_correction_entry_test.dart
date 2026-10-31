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
    'status': 'submitted',
    'attachment_paths': <String>[],
    'expires_at': null,
    'notes': null,
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
      for (final code in ['PGRST202', '42501']) {
        bool? handled;
        await host(
          tester,
          (action, data) async =>
              throw PostgrestException(message: 'unavailable', code: code),
          (value) => handled = value,
        );
        expect(handled, false);
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
    'exact capability opens distinct correction and expiry/reason save keeps snapshot',
    (tester) async {
      bool? handled;
      Map<String, dynamic>? saved;
      await host(tester, (action, data) async {
        if (action == 'capability') {
          return capability(true);
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
      expect(saved?['expected_snapshot'], snapshot);
      expect((saved?['fields'] as Map)['expires_at'], '2030-01-01');
      expect(saved?['reason'], '期限の入力漏れを訂正');
      expect(preferences.getKeys(), isEmpty);
    },
  );
}
