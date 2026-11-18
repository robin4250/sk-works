import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:sk_works/features/attendance/worker_attendance_sheet_repository.dart';
import 'package:sk_works/features/personal_vault/retirement_pdf_renderer.dart';
import 'package:sk_works/features/people/employee_retirement_page.dart';
import 'package:sk_works/features/people/employee_retirement_repository.dart';
import 'package:sk_works/features/people/people_cloud_repository.dart';
import 'package:sk_works/features/personal_vault/personal_vault_repository.dart';
import 'package:sk_works/features/personal_vault/personal_vault_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'admin retirement is followed by opening all three documents as the original employee',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      const actor = '20000000-0000-4000-8000-000000000001';
      const company = '30000000-0000-4000-8000-000000000001';
      const requestId = '40000000-0000-4000-8000-000000000001';
      const admin = '50000000-0000-4000-8000-000000000001';
      const worker = '60000000-0000-4000-8000-000000000001';
      final documents = [
        (
          key: 'a' * 64,
          kind: 'own_qualification_image',
          mime: 'image/png',
          ext: 'png',
          label: '資格証画像',
        ),
        (
          key: 'b' * 64,
          kind: 'own_payroll',
          mime: 'application/pdf',
          ext: 'pdf',
          label: '給与明細',
        ),
        (
          key: 'c' * 64,
          kind: 'own_attendance',
          mime: 'application/pdf',
          ext: 'pdf',
          label: '本人出勤表',
        ),
      ];
      const queueTest = true;
      const verificationServer = String.fromEnvironment('SKO_RETIREMENT_TEST_SERVER');
      final vault = <String, Uint8List>{};
      final date = DateTime(2026, 10, 16);
      const preparedPayroll = String.fromEnvironment('SKO_TEST_PAYROLL_PDF');
      const preparedAttendance = String.fromEnvironment('SKO_TEST_ATTENDANCE_PDF');
      final hasPreparedPdfs = preparedPayroll.isNotEmpty && preparedAttendance.isNotEmpty;
      final renderer = hasPreparedPdfs ? null : await tester.runAsync(() async => RetirementPdfRenderer(
        regularFont: pw.Font.ttf(await rootBundle.load('assets/fonts/web-ui/NotoSansJP-Regular.ttf')),
        boldFont: pw.Font.ttf(await rootBundle.load('assets/fonts/company-seal/NotoSansJP-Bold.ttf')),
      ));

      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4//8/AAX+Av4N70a4AAAAAElFTkSuQmCC',
      );
      String part(Object value) =>
          base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
      String token(String user) =>
          '${part({'alg': 'HS256'})}.${part({'sub': user, 'session_id': user, 'exp': 4102444800})}.fixture';
      String session(String user) => jsonEncode({
        'access_token': token(user),
        'refresh_token': 'fixture',
        'token_type': 'bearer',
        'user': {
          'id': user,
          'aud': 'authenticated',
          'created_at': '2026-11-17T00:00:00Z',
          'app_metadata': {},
          'user_metadata': {},
        },
      });
      final downloaded = <String>{};
      var retired = false;
      var queued = false;
      String path(String key, String ext) => 'personal-vault/$actor/$key.$ext';
      Future<void> saveFixtureArchive() async {
            if (verificationServer.isNotEmpty) {
              final reply = await http.post(Uri.parse(verificationServer));
              expect(reply.statusCode, 200, reason: reply.body);
              final files = jsonDecode(reply.body) as Map;
              for (final doc in documents) {
                vault[doc.key] = base64Decode(files[doc.kind] as String);
              }
            } else if (hasPreparedPdfs) {
              vault.addAll({documents[0].key:png, documents[1].key:base64Decode(preparedPayroll),
                documents[2].key:base64Decode(preparedAttendance)});
            } else {
              final payroll = await renderer!.payroll({
                'sourceId': 'fixture-payroll', 'revision': '1',
                'companyName': '検証会社', 'workerName': '検証社員',
                'periodStart': '2026-10-01', 'periodEnd': '2026-10-31',
                'issuedAt': '2026-11-01T00:00:00Z',
                'hasAdditionalAdjustments': false,
                'result': {'gross_pay': 100000, 'deductions': 10000, 'net_pay': 90000},
                'detail': {'基本給': 100000, '所得税': 10000, '出勤日数': 1},
              }, verifiedPersonId: actor, snapshotPersonId: actor, companyId: company);
              final attendance = await renderer.attendance(
                WorkerAttendanceMonth(year: 2026, month: 10, days: {
                  date: WorkerAttendanceDay(date: date, siteName: '検証現場',
                    manDays: 1, clockIn: DateTime(2026, 10, 16, 8),
                    clockOut: DateTime(2026, 10, 16, 17)),
                }),
                workerName: '検証社員', cutoff: DateTime(2026, 11, 17),
              );
              expect(payroll, isNot(equals(attendance)));
              vault.addAll({documents[0].key: png, documents[1].key: payroll,
                documents[2].key: attendance});
            }
            retired = true;
      }
      http.Client makeHttp() => MockClient((request) async {
        http.Response json(Object result) => http.Response(
          jsonEncode(result),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
        final endpoint = request.url.path;
        if (request.headers['Authorization'] == 'Bearer ${token(admin)}') {
          if (endpoint.endsWith('/company_members')) {
            return json([
              {'company_id': company, 'role': 'admin'},
            ]);
          }
          if (endpoint.endsWith('/employee_personnel_view')) {
            return json({
              'company_id': company,
              'records': [
                {
                  'id': worker,
                  'kind': 'employee',
                  'active': !retired,
                  'name': 'Fixture',
                },
              ],
            });
          }
          if (endpoint.endsWith('/retirement_render_state_pilot')) {
            return json(retired ? 'completed' : queued ? 'pending' : 'none');
          }
          if (endpoint.endsWith('/request_retirement_render_pilot')) {
            expect(jsonDecode(request.body), {'p_company':company,'p_worker':worker});
            queued = true;
            return json(requestId);
          }
          if (endpoint.endsWith('/retire-employee-with-archive')) {
            expect(jsonDecode(request.body), {
              'p_company_id': company,
              'p_worker_id': worker,
            });
            await saveFixtureArchive();
            return json({'retired': true});
          }
          expect(endpoint, '/rest/v1/workers');
          return json([
            {
              'id': worker,
              'company_id': company,
              'status': retired ? 'inactive' : 'active',
            },
          ]);
        }
        expect(request.headers['Authorization'], 'Bearer ${token(actor)}');
        if (endpoint == '/rest/v1/rpc/retirement_vault_list_mine') {
          return json([
            if (retired)
              for (final doc in documents)
                {
                  'request_id': requestId,
                  'artifact_key': doc.key,
                  'source_company_id': company,
                  'completed_at': '2026-11-17T03:00:00Z',
                  'kind': doc.kind,
                  'content_type': doc.mime,
                },
          ]);
        }
        expect(retired, isTrue);
        if (endpoint == '/rest/v1/rpc/retirement_vault_item_mine') {
          final params = jsonDecode(request.body) as Map;
          expect(params['rid'], requestId);
          final doc = documents.singleWhere(
            (doc) => doc.key == params['artifact'],
          );
          final bytes = vault[doc.key]!;
          return json([
            {
              'object_path': path(doc.key, doc.ext),
              'object_version': 'stored-v1',
              'content_type': doc.mime,
              'sha256': sha256.convert(bytes).toString(),
              'byte_length': bytes.length,
            },
          ]);
        }
        final doc = documents.singleWhere(
          (doc) =>
              endpoint ==
              '/storage/v1/object/authenticated/retirement-private-vault/${path(doc.key, doc.ext)}',
        );
        downloaded.add(doc.key);
        return http.Response.bytes(
          vault[doc.key]!,
          200,
          headers: {'content-type': doc.mime},
          request: request,
        );
      });
      late final SupabaseClient client;
      await tester.runAsync(() async {
        client = SupabaseClient(
          'https://retirement-fixture.invalid',
          'fixture',
          httpClient: makeHttp(),
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        );
        await client.auth.setInitialSession(session(admin));
      });
      addTearDown(() => tester.runAsync(client.dispose));
      final privacy = PersonnelPrivacySession(
        actor: admin,
        company: company,
        currentActor: () => admin,
        load: () async => throw UnimplementedError(),
      );
      privacy.snapshot = const PersonnelPrivacySnapshot(
        actor: admin,
        company: company,
        role: 'admin',
        canManage: true,
        records: [
          {'id': worker, 'active': true},
        ],
      );
      addTearDown(privacy.dispose);
      Future<void> pumpUntil(bool Function() ready) async {
        for (var attempt = 0; attempt < (verificationServer.isEmpty ? 120 : 1800) && !ready(); attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await tester.pump(const Duration(milliseconds: 30));
        }
        expect(ready(), isTrue);
      }

      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => EmployeeRetirementPage(
                        companyId: company,
                        workerId: worker,
                        workerName: 'Fixture',
                        privacySession: privacy,
                        repository: EmployeeRetirementRepository(client),
                      ),
                    ),
                  ),
                  child: const Text('退職手続きを開く'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('退職手続きを開く'));
        await pumpUntil(
          () => find.byType(CheckboxListTile).evaluate().isNotEmpty,
        );
        await tester.tap(find.byType(CheckboxListTile));
        await tester.pump();
        await tester.tap(find.text('退職として登録'));
        if (queueTest) {
          await pumpUntil(() => find.text('処理状況を確認').evaluate().isNotEmpty);
          expect(queued,isTrue);
          expect(retired,isFalse);
          expect(vault,isEmpty);
          await tester.tap(find.text('処理状況を確認'));
          await pumpUntil(() => find.widgetWithText(FilledButton,'処理状況を確認').evaluate().any(
            (element) => (element.widget as FilledButton).onPressed != null));
          expect(retired,isFalse);
          await saveFixtureArchive();
          await tester.tap(find.text('処理状況を確認'));
        }
        await pumpUntil(
          () => retired && find.byType(CheckboxListTile).evaluate().isEmpty,
        );

        await client.auth.setInitialSession(session(actor));
        expect(client.auth.currentUser?.id, actor);
        await tester.pumpWidget(
          MaterialApp(
            key: const ValueKey('employee'),
            home: PersonalVaultScreen(
              client: client,
              retirementArchive: true,
              repository: PersonalVaultRepository(
                client,
                retirementArchive: true,
                downloadClientFactory: makeHttp,
              ),
            ),
          ),
        );
        for (final doc in [...documents.skip(1), documents.first]) {
          await pumpUntil(
            () => find.text(doc.label).hitTestable().evaluate().isNotEmpty,
          );
          await tester.tap(find.text(doc.label));
          final preview = doc.ext == 'png' ? RawImage : PdfPreview;
          await pumpUntil(
            () =>
                downloaded.contains(doc.key) &&
                find.byType(preview).evaluate().isNotEmpty,
          );
          if (doc.ext == 'pdf') {
            final widget = tester.widget<PdfPreview>(find.byType(PdfPreview));
            final verified = await widget.build(PdfPageFormat.a4);
            expect(verified, vault[doc.key]);
            tester.state<NavigatorState>(find.byType(Navigator).first).pop();
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 400));
            await pumpUntil(() => find.byType(PdfPreview).evaluate().isEmpty);
          }
        }
      });
      expect(downloaded, documents.map((doc) => doc.key).toSet());
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.runAsync(() async {
        for (
          var attempt = 0;
          attempt < 30 && find.byType(RawImage).evaluate().isNotEmpty;
          attempt++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await tester.pump(const Duration(milliseconds: 30));
        }
      });
      expect(find.byType(RawImage), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
