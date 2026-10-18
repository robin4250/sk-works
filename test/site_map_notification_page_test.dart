import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/sites/site_map_notification_page.dart';
import 'package:sk_works/international/language_controller.dart';
import 'package:sk_works/international/language_pack_registry.dart';

const id = '11111111-1111-4111-8111-111111111111';
const company = '22222222-2222-4222-8222-222222222222';
const worker = '33333333-3333-4333-8333-333333333333';
Map<String, dynamic> saved() => {
  'id': id,
  'company_id': company,
  'worker_id': worker,
  'confirmed_at': '2026-09-01T16:30:00Z',
  'event_type': 'clock_out',
  'latitude': 35.125,
  'longitude': 139.25,
  'workers': {'name': '通知の社員'},
  'sites': {'name': '保存された現場'},
};

class Source implements SiteMapNoticeSource {
  @override
  String? actor = 'actor-a';
  final changes = StreamController<String?>.broadcast(sync: true);
  @override
  Stream<String?> get actorChanges => changes.stream;
  Map<String, dynamic>? row = saved();
  Completer<Map<String, dynamic>?>? pending;
  bool denied = false;
  final calls = <String>[];
  @override
  Future<Map<String, dynamic>?> target(String id) async {
    calls.add(id);
    if (denied) throw StateError('private backend details');
    return pending == null ? row : pending!.future;
  }

  void change(String? value) {
    actor = value;
    changes.add(value);
  }
}

void main() {
  setUp(
    () => SkoLanguageController.pack.value = LanguagePackRegistry.resolve('ja'),
  );
  tearDown(
    () => SkoLanguageController.pack.value = LanguagePackRegistry.resolve('ja'),
  );
  Future<void> open(
    WidgetTester tester,
    Source source, {
    String target = id,
    Future<bool> Function(Uri)? opener,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SiteMapNotificationPage(
          verificationId: target,
          source: source,
          openMap: opener,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  test(
    'typed target rejects missing, wrong, malformed and nonfinite saved values',
    () {
      final bad = <Map<String, dynamic>>[
        {...saved(), 'id': company},
        {...saved(), 'company_id': ''},
        {...saved(), 'worker_id': 'worker'},
        {...saved(), 'latitude': null},
        {...saved(), 'longitude': '139'},
        {...saved(), 'latitude': double.nan},
        {...saved(), 'longitude': double.infinity},
        {...saved(), 'latitude': 90.1},
        {...saved(), 'longitude': -180.1},
        {...saved(), 'confirmed_at': '2026-09-01T16:30:00'},
        {...saved(), 'confirmed_at': '2026-02-30T16:30:00Z'},
        {...saved(), 'confirmed_at': '2026-09-01T24:30:00Z'},
        {...saved(), 'confirmed_at': '2026-09-01T16:30:00+99:00'},
      ];
      for (final row in bad) {
        expect(
          () => SiteMapNoticeTarget.fromRow(id, row),
          throwsFormatException,
        );
      }
      expect(
        SiteMapNoticeTarget.fromRow(id, {
          ...saved(),
          'latitude': 0,
          'longitude': 0,
        }).latitude,
        0,
      );
      expect(
        SiteMapNoticeTarget.fromRow(id, {
          ...saved(),
          'latitude': -90,
          'longitude': 180,
        }).longitude,
        180,
      );
    },
  );

  testWidgets('mounted in background does not read until resumed', (
    tester,
  ) async {
    final source = Source();
    addTearDown(source.changes.close);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await open(tester, source);
    expect(source.calls, isEmpty);
    expect(find.text('通知の社員'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(source.calls, [id]);
    expect(find.text('通知の社員'), findsOneWidget);
  });

  testWidgets(
    'saved historical event renders JST and opens only on explicit tap',
    (tester) async {
      final source = Source();
      addTearDown(source.changes.close);
      final opened = <Uri>[];
      await open(
        tester,
        source,
        opener: (uri) async {
          opened.add(uri);
          return true;
        },
      );
      expect(source.calls, [id]);
      expect(find.text('2026/09/02 01:30 JST'), findsOneWidget);
      expect(find.text('通知の社員'), findsOneWidget);
      expect(find.text('保存された現場'), findsOneWidget);
      expect(opened, isEmpty);
      await tester.tap(find.text('Google マップで開く'));
      await tester.pump();
      expect(opened.single.scheme, 'https');
      expect(opened.single.host, 'www.google.com');
      expect(opened.single.path, '/maps/search/');
      expect(opened.single.queryParameters, {
        'api': '1',
        'query': '35.125,139.25',
      });
      expect(source.calls, [id]);
    },
  );

  testWidgets('invalid UUID makes no request and no map action', (
    tester,
  ) async {
    final source = Source();
    addTearDown(source.changes.close);
    await open(tester, source, target: '../latest');
    expect(source.calls, isEmpty);
    expect(find.byType(FilledButton), findsNothing);
  });

  for (final missing in [true, false]) {
    testWidgets(
      missing
          ? 'missing record never falls back'
          : 'denied record never exposes error body',
      (tester) async {
        final source = Source()
          ..row = null
          ..denied = !missing;
        addTearDown(source.changes.close);
        await open(tester, source);
        expect(source.calls, [id]);
        expect(find.byType(FilledButton), findsNothing);
        expect(find.textContaining('private backend'), findsNothing);
        expect(find.text('再読み込み'), findsOneWidget);
      },
    );
  }

  testWidgets('invalid coordinates never display names or open map', (
    tester,
  ) async {
    final source = Source()..row = {...saved(), 'longitude': double.nan};
    addTearDown(source.changes.close);
    await open(tester, source);
    expect(find.text('通知の社員'), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('signed-out actor never reads', (tester) async {
    final source = Source()..actor = null;
    addTearDown(source.changes.close);
    await open(tester, source);
    expect(source.calls, isEmpty);
  });

  testWidgets(
    'A-B-A invalidation stays sticky and prevents reload and map launch',
    (tester) async {
      final source = Source();
      addTearDown(source.changes.close);
      final opened = <Uri>[];
      await open(
        tester,
        source,
        opener: (uri) async {
          opened.add(uri);
          return true;
        },
      );
      source.change('actor-b');
      source.change('actor-a');
      await tester.pump();
      expect(find.text('通知の社員'), findsNothing);
      expect(find.text('再読み込み'), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
      expect(opened, isEmpty);
      expect(source.calls, [id]);
    },
  );

  testWidgets('late result after actor change cannot repopulate', (
    tester,
  ) async {
    final source = Source()..pending = Completer();
    addTearDown(source.changes.close);
    await open(tester, source);
    source.change('actor-b');
    source.change('actor-a');
    source.pending!.complete(saved());
    await tester.pumpAndSettle();
    expect(find.text('通知の社員'), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('unannounced actor change is checked again at map tap', (
    tester,
  ) async {
    final source = Source();
    addTearDown(source.changes.close);
    final opened = <Uri>[];
    await open(
      tester,
      source,
      opener: (uri) async {
        opened.add(uri);
        return true;
      },
    );
    source.actor = 'actor-b';
    await tester.tap(find.text('Google マップで開く'));
    await tester.pump();
    expect(opened, isEmpty);
    expect(find.text('通知の社員'), findsNothing);
  });

  testWidgets(
    'background clears location and resumed load uses same saved ID',
    (tester) async {
      final source = Source();
      addTearDown(source.changes.close);
      await open(tester, source);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.text('通知の社員'), findsNothing);
      source.row = {...saved(), 'latitude': 34.5};
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(source.calls, [id, id]);
      expect(find.text('34.5, 139.25'), findsOneWidget);
    },
  );

  testWidgets(
    'late pre-background result cannot replace resumed saved target',
    (tester) async {
      final old = Completer<Map<String, dynamic>?>();
      final source = Source()..pending = old;
      addTearDown(source.changes.close);
      await open(tester, source);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      source.pending = null;
      source.row = {...saved(), 'latitude': 34.5};
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      old.complete(saved());
      await tester.pumpAndSettle();
      expect(source.calls, [id, id]);
      expect(find.text('34.5, 139.25'), findsOneWidget);
      expect(find.text('35.125, 139.25'), findsNothing);
    },
  );

  testWidgets('actor stream failure hides saved location permanently', (
    tester,
  ) async {
    final source = Source();
    addTearDown(source.changes.close);
    await open(tester, source);
    source.changes.addError(StateError('private detail'));
    await tester.pump();
    expect(find.text('通知の社員'), findsNothing);
    expect(find.textContaining('private detail'), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('resume with actor changed is sticky', (tester) async {
    final source = Source();
    addTearDown(source.changes.close);
    await open(tester, source);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    source.actor = 'actor-b';
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(source.calls, [id]);
    expect(find.byType(FilledButton), findsNothing);
    source.actor = 'actor-a';
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(source.calls, [id]);
  });

  testWidgets('disposed late result never updates or launches', (tester) async {
    final source = Source()..pending = Completer();
    addTearDown(source.changes.close);
    await open(tester, source);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    source.pending!.complete(saved());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'map launch failure keeps exact saved target and offers normal message',
    (tester) async {
      final source = Source();
      addTearDown(source.changes.close);
      await open(tester, source, opener: (_) async => false);
      await tester.tap(find.text('Google マップで開く'));
      await tester.pump();
      expect(find.text('地図を開けませんでした。もう一度お試しください。'), findsOneWidget);
      expect(source.calls, [id]);
      expect(find.text('通知の社員'), findsOneWidget);
    },
  );

  testWidgets('English UI uses readable translated labels', (tester) async {
    SkoLanguageController.pack.value = LanguagePackRegistry.resolve('en');
    final source = Source();
    addTearDown(source.changes.close);
    await open(tester, source);
    expect(find.text('Location from this notification'), findsOneWidget);
    expect(find.text('Open in Google Maps'), findsOneWidget);
  });
}
