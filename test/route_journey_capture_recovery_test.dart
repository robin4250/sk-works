import 'dart:async';
import 'package:sk_works/features/attendance/attendance_verification_page.dart';
import 'package:sk_works/features/attendance/attendance_selection_page.dart';
import 'package:sk_works/features/attendance/work_destination_selection_page.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/attendance/gps_photo_capture_result.dart';
import 'package:sk_works/international/language_controller.dart';
import 'package:sk_works/international/language_pack_registry.dart';
import 'package:sk_works/features/attendance/route_journey_capture_draft.dart';
import 'package:sk_works/features/attendance/route_journey_capture_page.dart';

class _Access implements RouteJourneyCaptureAccess {
  @override
  String userId = 'actor';
  bool failAll = false, failWorkspace = false;
  List<Map<String, dynamic>>? visits;
  bool archived = false;
  int loads = 0, submits = 0, uploads = 0;
  final sources = <String>[];
  RouteJourneyCaptureDraft? pending, submitted;
  Completer<List<RouteJourneyCaptureDraft>>? delayed;
  @override
  Future<List<RouteJourneyCaptureDraft>> allPending() async {
    loads++;
    if (failAll) throw StateError('offline');
    if (delayed != null) return delayed!.future;
    return [if (pending != null) pending!];
  }

  @override
  Future<Map<String, dynamic>> workspace(String sourceId) async {
    sources.add(sourceId);
    if (failWorkspace) throw StateError('offline');
    return {
      if (visits != null) 'visit_contract_version': 1,
      if (visits != null) 'visits': visits,
      'company_id': 'company',
      'source_clock_in_id': sourceId,
      'work_date': '2026-10-10',
      'enabled': !archived,
      'is_open': !archived,
      'archived': archived,
      'origin_kind': 'company',
      'route_assignment_id': 'route',
      'worker_id': 'worker',
      'stops': [
        {'id': 'stop', 'stop_order': 1, 'label': 'Test site'},
      ],
    };
  }

  @override
  Future<RouteJourneyCaptureDraft?> loadPending(String companyId) async =>
      pending;
  @override
  Future<Map<String, dynamic>> submit(RouteJourneyCaptureDraft draft) async {
    submits++;
    submitted = draft;
    throw StateError('Unconfirmed result');
  }

  @override
  Future<String> upload(
    CapturedPhoto photo,
    CaptureShiftContext context,
    String workerId,
  ) async {
    uploads++;
    throw StateError('Must not capture during reload');
  }
}

Future<void> _open(WidgetTester tester, _Access access) async {
  await tester.binding.setSurfaceSize(const Size(600, 1100));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: RouteJourneyCapturePage(sourceId: 'source', access: access),
    ),
  );
  await tester.pumpAndSettle();
}

Finder get _reload => find.widgetWithText(OutlinedButton, '再読み込み');
void main() {
  for (final selection in [0, 1, 2, 3]) {
    testWidgets(
      'back stays reachable with hidden home chrome: selection=$selection',
      (tester) async {
        final access = _Access()..visits = [];
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(appBarTheme: const AppBarTheme(toolbarHeight: 0)),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => switch (selection) {
                        0 => RouteJourneyCapturePage(
                          sourceId: 'source',
                          access: access,
                        ),
                        1 => const WorkDestinationSelectionPage(),
                        2 => const AttendanceSelectionPage(),
                        _ => const AttendanceVerificationPage(),
                      },
                    ),
                  ),
                  child: const Text('Open work page'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open work page'));
        await tester.pumpAndSettle();
        expect(find.byType(BackButton).hitTestable(), findsOneWidget);
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(find.text('Open work page'), findsOneWidget);
        expect(access.submits, 0);
      },
    );
  }

  testWidgets(
    'archived source explains preservation without new capture action',
    (tester) async {
      final access = _Access()
        ..visits = []
        ..archived = true;
      await _open(tester, access);
      expect(find.textContaining('変更前の記録は保持されています'), findsOneWidget);
      expect(find.text('この現場の作業を開始'), findsNothing);
      expect(access.submits, 0);
    },
  );

  testWidgets(
    'visit workspace offers start without silently selecting a stop',
    (tester) async {
      final access = _Access()..visits = [];
      await _open(tester, access);
      expect(find.text('この現場の作業を開始'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(access.submits, 0);
    },
  );
  testWidgets('open visit offers only end and locks its selected stop', (
    tester,
  ) async {
    final access = _Access()
      ..visits = [
        {
          'start_capture_id': 'start',
          'route_stop_id': 'stop',
          'stop_label': 'Test site',
          'work_date': '2026-10-10',
          'started_at': '2026-10-10T09:00:00Z',
          'ended_at': null,
          'end_capture_id': null,
        },
      ];
    await _open(tester, access);
    expect(find.text('この現場の作業を終了'), findsOneWidget);
    expect(find.text('この現場の作業を開始'), findsNothing);
    expect(find.textContaining('作業中'), findsOneWidget);
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byType(DropdownButtonFormField<String>),
          )
          .onChanged,
      isNull,
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    expect(access.submits, 0);
  });
  testWidgets(
    'ambiguous open visits fail closed instead of offering a new start',
    (tester) async {
      final visit = <String, dynamic>{
        'start_capture_id': 'start',
        'route_stop_id': 'stop',
        'stop_label': 'Test site',
        'work_date': '2026-10-10',
        'started_at': '2026-10-10T09:00:00Z',
        'ended_at': null,
        'end_capture_id': null,
      };
      final access = _Access()..visits = [visit, visit];
      await _open(tester, access);
      expect(_reload, findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(access.submits, 0);
    },
  );

  testWidgets('initial pending read failure retries without writes', (
    tester,
  ) async {
    final access = _Access()..failAll = true;
    await _open(tester, access);
    expect(_reload, findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    access.failAll = false;
    await tester.tap(_reload);
    await tester.pumpAndSettle();
    expect(find.text('勤務日: 2026-10-10'), findsOneWidget);
    expect(_reload, findsNothing);
    expect(access.sources, ['source']);
    expect(access.submits, 0);
    expect(access.uploads, 0);
  });
  testWidgets(
    'workspace retry preserves recovered command UUID even if next listing is empty',
    (tester) async {
      final draft = RouteJourneyCaptureDraft(
        userId: 'actor',
        companyId: 'company',
        sourceId: 'source',
        stopId: 'stop',
        originKind: 'company',
        payload: {
          'capture_contract_version': 1,
          'photo_storage_path': 'saved/photo.jpg',
        },
      );
      final access = _Access()
        ..pending = draft
        ..failWorkspace = true;
      await _open(tester, access);
      expect(find.textContaining('保留中の対象'), findsOneWidget);
      access.pending = null;
      access.failWorkspace = false;
      await tester.tap(_reload);
      await tester.pumpAndSettle();
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(access.sources, ['source', 'source']);
      expect(access.submits, 0);
      await tester.tap(find.text('同じ途中現場記録で再確認'));
      await tester.pumpAndSettle();
      expect(access.submits, 1);
      expect(access.uploads, 0);
      expect(identical(access.submitted, draft), isTrue);
      expect(access.submitted!.encoded, draft.encoded);
    },
  );
  testWidgets(
    'duplicate retry callbacks share one read and disable all write actions',
    (tester) async {
      final access = _Access()..failAll = true;
      await _open(tester, access);
      final retry = tester.widget<OutlinedButton>(_reload).onPressed!;
      access.failAll = false;
      access.delayed = Completer<List<RouteJourneyCaptureDraft>>();
      retry();
      retry();
      await tester.pump();
      expect(access.loads, 2);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
      access.delayed!.complete([]);
      await tester.pumpAndSettle();
      expect(access.sources, ['source']);
      expect(access.submits, 0);
      expect(access.uploads, 0);
    },
  );
  testWidgets(
    'leaving ignores delayed read and does not continue to workspace',
    (tester) async {
      final access = _Access()..failAll = true;
      await _open(tester, access);
      access.failAll = false;
      access.delayed = Completer<List<RouteJourneyCaptureDraft>>();
      await tester.tap(_reload);
      await tester.pump();
      await tester.pumpWidget(const MaterialApp(home: Text('Previous page')));
      access.delayed!.complete([]);
      await tester.pumpAndSettle();
      expect(access.sources, isEmpty);
      expect(access.submits, 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'changed actor rejects old read and cannot retry into the new account',
    (tester) async {
      final access = _Access()..failAll = true;
      await _open(tester, access);
      access.failAll = false;
      access.delayed = Completer<List<RouteJourneyCaptureDraft>>();
      await tester.tap(_reload);
      await tester.pump();
      access.userId = 'other';
      access.delayed!.complete([]);
      await tester.pumpAndSettle();
      expect(_reload, findsOneWidget);
      expect(access.sources, isEmpty);
      await tester.tap(_reload);
      await tester.pumpAndSettle();
      expect(access.loads, 2);
      expect(access.submits, 0);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
    },
  );
  testWidgets('English recovery fits a narrow screen with larger text', (
    tester,
  ) async {
    final previous = SkoLanguageController.pack.value;
    SkoLanguageController.pack.value = LanguagePackRegistry.resolve('en');
    addTearDown(() => SkoLanguageController.pack.value = previous);
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final access = _Access()..failAll = true;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: RouteJourneyCapturePage(sourceId: 'source', access: access),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Reload'), findsOneWidget);
    expect(
      find.text('Could not load the shift. Retry to check the same record.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
