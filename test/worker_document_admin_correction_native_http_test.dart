import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/people/worker_document_admin_correction_entry.dart';
import 'package:sk_works/features/people/worker_document_admin_correction_repository.dart';

void main() {
  final contextPath = Platform.environment['SKO_DOCUMENT_NATIVE_HTTP_CONTEXT'];
  testWidgets(
    'actual SDK list projection to inspect to form to same Native full-row CAS',
    (tester) async {
      final config = jsonDecode(File(contextPath!).readAsStringSync()) as Map;
      final previousOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = previousOverrides);
      final client = SupabaseClient(
        config['url'] as String,
        config['token'] as String,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      addTearDown(client.dispose);
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      Future<Map<String, dynamic>> readProjection() async {
        final response = await http.get(
          Uri.parse('${config['url']}/fixture-context'),
          headers: {'Authorization': 'Bearer ${config['token']}'},
        );
        expect(response.statusCode, 200);
        return Map<String, dynamic>.from(
          (jsonDecode(response.body) as Map)['projection'] as Map,
        );
      }

      final projected = (await tester.runAsync(readProjection))!;
      expect(projected.containsKey('updated_by'), false);
      expect(projected.containsKey('template_version_id'), false);
      Map<String, dynamic>? command;
      final repository = WorkerDocumentAdminCorrectionRepository.forTesting(
        actor: config['actor'] as String,
        companyId: config['company'] as String,
        targetId: config['target'] as String,
        preferences: preferences,
        requireCurrent: () {},
        rpc: (action, data) async {
          if (action == 'correct') {
            command = data;
          }
          return client.rpc(
            'worker_document_admin_self_correction',
            params: {'p_action': action, 'p_data': data},
          );
        },
      );
      bool? handled;
      Object? failure;
      Future<void> waitFor(bool Function() ready) async {
        for (var i = 0; i < 100; i++) {
          await tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 25));
          });
          await tester.pump(const Duration(milliseconds: 10));
          if (ready()) {
            return;
          }
        }
        fail('Native document HTTP operation did not reach expected UI state');
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  try {
                    handled = await openWorkerDocumentAdminCorrection(
                      context: context,
                      repository: repository,
                      snapshot: projected,
                      documentName: 'Native fixture document',
                      isCurrentTarget: () => true,
                    );
                  } catch (error) {
                    failure = error;
                  }
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await waitFor(
        () =>
            find
                .widgetWithText(FilledButton, '変更を保存')
                .evaluate()
                .any((e) => (e.widget as FilledButton).onPressed != null) ||
            failure != null,
      );
      expect(failure, isNull);
      expect(find.text('本人書類の管理訂正'), findsOneWidget);
      await tester.enterText(find.byType(TextField).at(0), '2040-01-01');
      await tester.enterText(
        find.byType(TextField).at(2),
        'Native actual projection correction',
      );
      await tester.ensureVisible(find.text('変更を保存'));
      await tester.tap(find.text('変更を保存'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('変更を保存').last);
      await waitFor(() => handled != null || failure != null);
      await tester.pumpAndSettle();
      expect(failure, isNull);
      expect(handled, true);
      expect(preferences.getKeys(), isEmpty);
      final reviewed = command!['expected_snapshot'] as Map;
      expect(reviewed.containsKey('updated_by'), true);
      expect(reviewed.containsKey('template_version_id'), true);
      final actual = await tester.runAsync(readProjection);
      expect(actual!['expires_at'], '2040-01-01');
      final receipt = await tester.runAsync(
        () => client.rpc(
          'worker_document_admin_self_correction',
          params: {
            'p_action': 'get',
            'p_data': {
              'company_id': config['company'],
              'target_id': config['target'],
              'request_id': command!['request_id'],
            },
          },
        ),
      );
      expect((receipt as Map)['status'], 'applied');
    },
    skip: contextPath == null ? 'dedicated Native HTTP fixture only' : false,
  );
}
