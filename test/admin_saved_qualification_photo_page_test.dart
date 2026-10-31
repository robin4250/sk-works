import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sk_works/features/qualifications/admin_saved_qualification_photo_page.dart';
import 'package:sk_works/features/qualifications/admin_saved_qualification_photo_submission_repository.dart';

import 'admin_saved_qualification_photo_live_sdk_test.dart'
    show Wire, actor, company, qualification;
import 'admin_saved_qualification_photo_submission_repository_test.dart'
    show Port, row;

class SaveWire extends Wire {
  Map<String, dynamic>? prepared;
  String status = 'draft';
  bool unknownSubmit = false;
  Future<void> Function(Map)? prepareObserver;
  final mutations = <String>[];
  @override
  Future<http.Response> respond(http.Request request) async {
    if (request.url.path == '/rest/v1/rpc/personal_qualification_submission') {
      final data = jsonDecode(request.body) as Map;
      final action = data['p_action'];
      if (action != 'admin_saved_photo_capability') {
        requests.add(request);
        final params = data['p_data'] as Map;
        if (action == 'prepare_admin_saved_photos') {
          await prepareObserver?.call(params);
          prepared = Map<String, dynamic>.from(params);
          mutations.add(action as String);
        }
        if (action == 'submit') {
          status = 'pending';
          mutations.add(action as String);
        }
        if (action == 'submit' && unknownSubmit) {
          return http.Response(
            jsonEncode({'message': 'unknown result', 'code': 'XX000'}),
            503,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        final value = {
          'version': 1,
          'id': prepared!['request_id'],
          'target_id': qualification,
          'requested_by': actor,
          'status': status,
          'cancelled': false,
          'reason': null,
          'photo_paths': [
            for (final slot in prepared!['photo_slots'] as List)
              slot['existing_path'],
          ],
          'upload_paths': <Object>[],
        };
        return http.Response(
          jsonEncode(value),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }
    }
    return super.respond(request);
  }
}

Future<void> waitFor(WidgetTester tester, Finder finder) async {
  final deadline = DateTime.now().add(const Duration(seconds: 12));
  while (finder.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  }
  if (finder.evaluate().isEmpty) {
    debugPrint('QUAL wait target absent');
  }
  expect(finder, findsOneWidget);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('old v1 backend has no actionable editor', (tester) async {
    final p = Port()..legacyCapability = true;
    final target = AdminSavedQualificationTarget(row());
    await tester.pumpWidget(
      MaterialApp(
        home: AdminSavedQualificationPhotoPage(
          row: row(),
          current: () => true,
          repository: AdminSavedQualificationSubmissionRepository(p, target),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('残す写真・順番を選ぶ'), findsNothing);
    expect(p.calls, ['admin_saved_photo_capability']);
  });
  testWidgets(
    'same State identity replacement permanently retires old editor',
    (tester) async {
      final p = Port();
      final target = AdminSavedQualificationTarget(row());
      final repository = AdminSavedQualificationSubmissionRepository(p, target);
      final saved = row();
      bool current() => true;
      await tester.pumpWidget(
        MaterialApp(
          home: AdminSavedQualificationPhotoPage(
            row: saved,
            current: current,
            repository: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('残す写真・順番を選ぶ'), findsOneWidget);
      final changed = {...saved, 'id': '10000000-0000-0000-0000-000000000099'};
      await tester.pumpWidget(
        MaterialApp(
          home: AdminSavedQualificationPhotoPage(
            row: changed,
            current: current,
            repository: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('残す写真・順番を選ぶ'), findsNothing);
      await tester.pumpWidget(
        MaterialApp(
          home: AdminSavedQualificationPhotoPage(
            row: saved,
            current: current,
            repository: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('残す写真・順番を選ぶ'), findsNothing);
      expect(p.calls, ['admin_saved_photo_capability']);
    },
  );
  for (final background in [false, true]) {
    testWidgets(
      'open confirmation masks on ${background ? 'background' : 'parent invalidation'}',
      (tester) async {
        final p = Port();
        final target = AdminSavedQualificationTarget(row());
        final invalidations = ValueNotifier(0);
        addTearDown(invalidations.dispose);
        if (background) {
          addTearDown(
            () => tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.resumed,
            ),
          );
        }
        await tester.pumpWidget(
          MaterialApp(
            home: AdminSavedQualificationPhotoPage(
              row: row(),
              current: () => true,
              repository: AdminSavedQualificationSubmissionRepository(
                p,
                target,
              ),
              invalidations: invalidations,
              photoBuilder: (_, __) => const Text('Synthetic retained image'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('残す写真・順番を選ぶ'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('選択を確認'));
        await tester.pumpAndSettle();
        expect(find.text('申請を送信'), findsOneWidget);
        if (background) {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
          await tester.pump();
          // Paused apps do not draw frames. Resume must keep the intent retired.
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        } else {
          invalidations.value++;
        }
        await tester.pumpAndSettle();
        expect(find.text('申請を送信'), findsNothing);
        expect(find.text('状態が変わりました'), findsOneWidget);
        expect(find.textContaining('2件から 2件'), findsNothing);
        expect(p.calls, ['admin_saved_photo_capability']);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }
  for (final osBack in [false, true]) {
    testWidgets(
      'owned draft returns locally via ${osBack ? 'OS back' : 'cancel'}',
      (tester) async {
        final p = Port();
        final target = AdminSavedQualificationTarget(row());
        final repository = AdminSavedQualificationSubmissionRepository(
          p,
          target,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: AdminSavedQualificationPhotoPage(
              row: row(),
              current: () => true,
              repository: repository,
              photoBuilder: (_, __) => const Text('Synthetic retained image'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('残す写真・順番を選ぶ'));
        await tester.pumpAndSettle();
        expect(find.text('資格写真の変更内容'), findsOneWidget);
        if (osBack) {
          await tester.binding.handlePopRoute();
        } else {
          await tester.tap(find.text('キャンセル'));
        }
        await tester.pumpAndSettle();
        expect(find.text('資格写真の変更内容'), findsNothing);
        expect(find.text('残す写真・順番を選ぶ'), findsOneWidget);
        expect(p.calls, ['admin_saved_photo_capability']);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'parent disposal masks a confirmation retained in the navigator',
    (tester) async {
      final p = Port();
      final target = AdminSavedQualificationTarget(row());
      final visible = ValueNotifier(true);
      addTearDown(visible.dispose);
      final repository = AdminSavedQualificationSubmissionRepository(p, target);
      final saved = row();
      bool current() => visible.value;
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<bool>(
            valueListenable: visible,
            builder: (_, show, __) => show
                ? AdminSavedQualificationPhotoPage(
                    row: saved,
                    current: current,
                    repository: repository,
                    photoBuilder: (_, __) =>
                        const Text('Synthetic retained image'),
                  )
                : const Scaffold(body: Text('Parent replaced')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('残す写真・順番を選ぶ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('選択を確認'));
      await tester.pumpAndSettle();
      expect(find.text('申請を送信'), findsOneWidget);
      visible.value = false;
      await tester.pumpAndSettle();
      expect(find.text('申請を送信'), findsNothing);
      expect(find.textContaining('2件から 2件'), findsNothing);
      expect(find.text('Parent replaced'), findsOneWidget);
      expect(p.calls, ['admin_saved_photo_capability']);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'actual SDK host selection confirmation fixed baseline submit and receipt',
    (tester) async {
      late SaveWire f;
      late LiveAdminSavedQualificationPort port;
      late Directory journalRoot;
      await tester.runAsync(() async {
        f = SaveWire();
        await f.login();
        debugPrint('QUAL login complete');
        journalRoot = await Directory.systemTemp.createTemp(
          'qualification-host-journal-fixture-',
        );
        port = LiveAdminSavedQualificationPort(
          f.client,
          f.target(),
          current: () => f.current,
          journalDirectory: () async => journalRoot,
        );
        await port.check();
        debugPrint('QUAL lease check complete');
      });
      final target = f.target();
      addTearDown(
        () => tester.runAsync(() async {
          await f.client.dispose();
          await journalRoot.delete(recursive: true);
        }),
      );
      final repo = AdminSavedQualificationSubmissionRepository(port, target);
      f.prepareObserver = (data) async {
        final stored =
            jsonDecode((await port.readJournal(repo.journalKey))!) as Map;
        expect(stored['stage'], 'prepare_started');
        expect(stored['request_id'], data['request_id']);
        debugPrint('QUAL flushed file intent observed before prepare');
      };
      await tester.pumpWidget(
        MaterialApp(
          home: AdminSavedQualificationPhotoPage(
            row: {},
            current: () => true,
            repository: repo,
            photoBuilder: (_, __) => const Text('Synthetic saved preview'),
          ),
        ),
      );
      debugPrint('QUAL host mounted');
      await waitFor(tester, find.text('残す写真・順番を選ぶ'));
      debugPrint('QUAL host capability loaded');
      await tester.tap(find.text('残す写真・順番を選ぶ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('選択から外す'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('選択を確認'));
      await tester.pumpAndSettle();
      expect(find.textContaining('1件から 0件'), findsOneWidget);
      await tester.runAsync(() => tester.tap(find.text('申請を送信')));
      await waitFor(tester, find.text('同じ申請を再確認'));
      expect(find.textContaining('申請受付を確認しました。'), findsOneWidget);
      debugPrint('QUAL fixed request receipt observed');
      expect(f.prepared!['expected_photo_paths'], ['synthetic/front']);
      expect(f.prepared!['photo_slots'], isEmpty);
      expect(f.prepared!['company_id'], company);
      expect(f.mutations, ['prepare_admin_saved_photos', 'submit']);
      expect(find.text('同じ申請を再確認'), findsOneWidget);
      expect(find.text('残す写真・順番を選ぶ'), findsNothing);
      expect(
        f.requests.where((r) => r.url.path.contains('/storage/')),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
    timeout: const Timeout(Duration(seconds: 40)),
  );
}
