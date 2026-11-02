import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// Existing pinned SDK transitive dependency; fixture explicitly owns its real isolate.
// ignore: depend_on_referenced_packages
import 'package:yet_another_json_isolate/yet_another_json_isolate.dart';
import 'package:sk_works/features/attendance/partner_attendance_month_page.dart';
import 'package:sk_works/features/attendance/worker_attendance_sheet_repository.dart';
import 'package:sk_works/international/language_controller.dart';
import 'package:sk_works/international/language_pack_registry.dart';
import 'partner_attendance_read_test.dart' show id, session;

void main() {
  testWidgets(
    'already stale worker is neutral from first frame and sends no HTTP',
    (tester) async {
      var calls = 0;
      final fixture = await _widgetClient(tester, (request) async {
        calls++;
        return http.Response('[]', 200, request: request);
      }, sid: 9);
      final client = fixture.$1;
      final worker = PartnerAttendanceWorker(
        id: id(3),
        name: 'PRIVATE OLD WORKER',
        companyId: id(2),
        partnerId: id(4),
        partnerName: 'PRIVATE OLD COMPANY',
        actorSession: '${id(1)}/${id(7)}',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: PartnerAttendanceMonthPage(
            worker: worker,
            initialMonth: DateTime(2026, 11),
            repositoryOverride: WorkerAttendanceSheetRepository.forClient(
              client,
            ),
          ),
        ),
      );
      expect(find.text('PRIVATE OLD WORKER'), findsNothing);
      expect(find.textContaining('PRIVATE OLD COMPANY'), findsNothing);
      expect(calls, 0);
      await tester.pumpAndSettle();
      expect(calls, 0);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await client.dispose();
        await fixture.$2.dispose();
      });
    },
  );

  testWidgets(
    'partner month JP/EN narrow layout filters site/route IDs and preserves source row IDs',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final original = SkoLanguageController.pack.value;
      addTearDown(() => SkoLanguageController.pack.value = original);
      for (final locale in ['ja', 'en']) {
        SkoLanguageController.pack.value = LanguagePackRegistry.resolve(locale);
        var denyMembership = false;
        final fixture = await _widgetClient(tester, (request) async {
          expect(request.method, 'GET');
          Object body;
          if (request.url.path.endsWith('company_members')) {
            body = denyMembership
                ? []
                : [
                    {'company_id': id(2)},
                  ];
          } else if (request.url.path.endsWith('workers')) {
            body = [
              {
                'id': id(3),
                'company_id': id(2),
                'partner_company_id': id(4),
                'affiliation': 'partner_company',
                'status': 'active',
              },
            ];
          } else {
            final date = request.url.queryParametersAll['work_date']!
                .firstWhere((value) => value.startsWith('gte.'))
                .substring(4);
            Map<String, Object?> row(int n) => {
              'id': id(n),
              'company_id': id(2),
              'worker_id': id(3),
              'work_date': date,
              'source_report_id': null,
              'base_man_days': 1,
              'overtime_hours': 0,
              'early_hours': 0,
              'night_hours': 0,
            };
            body = [
              {
                ...row(5),
                'site_id': id(6),
                'route_assignment_id': null,
                'sites': {
                  'id': id(6),
                  'name': 'Synthetic site',
                  'company_id': id(2),
                },
              },
              {
                ...row(10),
                'site_id': null,
                'route_assignment_id': id(11),
                'sites': null,
              },
            ];
          }
          return http.Response(
            jsonEncode(body),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        });
        final client = fixture.$1;
        final repository = _ObservedRepository(client);
        final worker = PartnerAttendanceWorker(
          id: id(3),
          name: 'Synthetic Worker',
          companyId: id(2),
          partnerId: id(4),
          partnerName:
              'Synthetic Partner Company With A Very Long Registered Name',
          actorSession: '${id(1)}/${id(7)}',
        );
        Widget app(String code) => MaterialApp(
          locale: Locale(code),
          supportedLocales: const [Locale('ja'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: PartnerAttendanceMonthPage(
            worker: worker,
            initialMonth: DateTime(2026, 11),
            repositoryOverride: repository,
          ),
        );
        expect(
          repository.partnerWorkerIsCurrent(worker),
          isTrue,
          reason: 'synthetic fixture must be current before first frame',
        );
        await tester.pumpWidget(app(locale));
        await tester.runAsync(() async {
          await repository.pending;
        });
        await tester.pumpAndSettle();
        expect(
          find.text(locale == 'en' ? 'Partner attendance' : '協力会社の出勤表'),
          findsOneWidget,
        );
        expect(find.byKey(ValueKey(id(5))), findsOneWidget);
        expect(find.byKey(ValueKey(id(10))), findsOneWidget);
        expect(tester.takeException(), isNull);
        final sameState = tester.state(find.byType(PartnerAttendanceMonthPage));
        final changedLocale = locale == 'ja' ? 'en' : 'ja';
        SkoLanguageController.pack.value = LanguagePackRegistry.resolve(
          changedLocale,
        );
        await tester.pumpWidget(app(changedLocale));
        await tester.pumpAndSettle();
        expect(
          tester.state(find.byType(PartnerAttendanceMonthPage)),
          same(sameState),
        );
        expect(
          find.text(changedLocale == 'en' ? 'Partner attendance' : '協力会社の出勤表'),
          findsOneWidget,
        );
        SkoLanguageController.pack.value = LanguagePackRegistry.resolve(locale);
        await tester.pumpWidget(app(locale));
        await tester.pumpAndSettle();

        await tester.tap(find.byType(DropdownButton<String>));
        await tester.runAsync(() async {
          await repository.pending;
        });
        await tester.pumpAndSettle();
        await tester.tap(
          find
              .text(
                locale == 'en'
                    ? 'Route work (no site assigned)'
                    : 'ルート勤務（現場指定なし）',
              )
              .last,
        );
        await tester.runAsync(() async {
          await repository.pending;
        });
        await tester.pumpAndSettle();
        expect(find.byKey(ValueKey(id(5))), findsNothing);
        expect(find.byKey(ValueKey(id(10))), findsOneWidget);
        await tester.tap(find.byIcon(Icons.chevron_right));
        await tester.runAsync(() async {
          await repository.pending;
        });
        await tester.pumpAndSettle();
        expect(
          find.text(locale == 'en' ? '2026/12' : '2026年12月'),
          findsOneWidget,
        );
        expect(find.byKey(ValueKey(id(5))), findsOneWidget);
        denyMembership = true;
        await tester.tap(find.byIcon(Icons.chevron_right));
        await tester.runAsync(() async {
          await repository.pending?.catchError(
            (Object _) => <Map<String, dynamic>>[],
          );
        });
        await tester.pumpAndSettle();
        expect(
          find.text(
            locale == 'en'
                ? 'Attendance records could not be loaded. Check your sign-in and company, then try again.'
                : '出勤記録を読み込めませんでした。ログイン状態と会社を確認して再試行してください。',
          ),
          findsOneWidget,
        );
        SkoLanguageController.pack.value = LanguagePackRegistry.resolve(
          changedLocale,
        );
        await tester.pumpWidget(app(changedLocale));
        await tester.pumpAndSettle();
        expect(
          tester.state(find.byType(PartnerAttendanceMonthPage)),
          same(sameState),
        );
        expect(
          find.text(
            changedLocale == 'en'
                ? 'Attendance records could not be loaded. Check your sign-in and company, then try again.'
                : '出勤記録を読み込めませんでした。ログイン状態と会社を確認して再試行してください。',
          ),
          findsOneWidget,
        );
        // recoverSession intentionally emits no event for the same UID in this SDK.
        // Exercise an actual auth-state notification, not a silent internal mutation.
        await client.auth.setInitialSession(jsonEncode(session(9)));
        await tester.pumpAndSettle();
        expect(find.text('Synthetic Worker'), findsNothing);
        expect(find.textContaining('Synthetic Partner Company'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() async {
          await client.dispose();
          await fixture.$2.dispose();
        });
      }
    },
  );
}

Future<(SupabaseClient, YAJsonIsolate)> _widgetClient(
  WidgetTester tester,
  Future<http.Response> Function(http.Request) handler, {
  int sid = 7,
}) async {
  return (await tester.runAsync(() async {
    final isolate = YAJsonIsolate();
    await isolate.initialize();
    final client = SupabaseClient(
      'https://fixture.invalid',
      'synthetic',
      isolate: isolate,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient(handler),
    );
    await client.auth.setInitialSession(jsonEncode(session(sid)));
    return (client, isolate);
  }))!;
}

class _ObservedRepository extends WorkerAttendanceSheetRepository {
  _ObservedRepository(super.client) : super.forClient();
  Future<List<Map<String, dynamic>>>? pending;
  @override
  Future<List<Map<String, dynamic>>> loadPartnerAttendanceMonth(
    PartnerAttendanceWorker worker,
    DateTime month,
  ) {
    return pending = super.loadPartnerAttendanceMonth(worker, month);
  }
}
