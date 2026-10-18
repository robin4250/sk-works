import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/operations/route_editor_page.dart';
import 'package:sk_works/features/operations/vehicle_route_repository.dart';

class _Routes implements VehicleRouteRepository {
  int saves = 0;
  String? savedId;
  String? savedName;
  List<Map<String, Object?>>? savedStops;
  final response = Completer<String>();

  @override
  Future<String> saveRoute({
    String? id,
    required String name,
    required String notes,
    String? responsibleName,
    String? responsiblePhone,
    required List<Map<String, Object?>> stops,
  }) {
    saves++;
    savedId = id;
    savedName = name;
    savedStops = stops;
    return response.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected repository call: ${invocation.memberName}');
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

Future<void> _open(
  WidgetTester tester,
  _Routes repository, {
  bool editing = false,
  ValueChanged<bool?>? result,
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              final changed = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => RouteEditorPage(
                    sites: const [],
                    customers: const [],
                    partners: const [],
                    vehicles: const [],
                    repository: repository,
                    route: editing
                        ? {'id': 'existing-route', 'route_name': '元のルート'}
                        : null,
                  ),
                ),
              );
              result?.call(changed);
            },
            child: const Text('一覧から開く'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('一覧から開く'));
  await tester.pumpAndSettle();
  await tester.enterText(_field('ルート名'), '保存するルート');
  await tester.enterText(_field('住所'), '保存する住所');
  await tester.ensureVisible(find.text('確定して保存'));
}

Future<void> _confirm(WidgetTester tester) async {
  final button = tester.widget<FilledButton>(
    find.widgetWithText(FilledButton, '確定して保存'),
  );
  button.onPressed!();
  button.onPressed!();
  await tester.pumpAndSettle();
  expect(find.byType(AlertDialog), findsOneWidget);
  await tester.tap(find.widgetWithText(FilledButton, '確定して保存'));
  await tester.pumpAndSettle();
}

void main() {
  for (final editing in [false, true]) {
    testWidgets(
      '${editing ? 'update' : 'register'} shows success only after save and returns to list once',
      (tester) async {
        final repository = _Routes();
        final results = <bool?>[];
        await _open(tester, repository, editing: editing, result: results.add);
        await _confirm(tester);
        expect(repository.saves, 1);
        expect(repository.savedId, editing ? 'existing-route' : null);
        expect(repository.savedName, '保存するルート');
        expect(repository.savedStops!.single['address'], '保存する住所');
        expect(find.text('保存完了'), findsNothing);
        expect(find.text('保存中…'), findsOneWidget);
        final save = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, '保存中…'),
        );
        expect(save.onPressed, isNull);
        repository.response.complete('existing-route');
        await tester.pumpAndSettle();
        expect(find.text('保存完了'), findsOneWidget);
        expect(
          find.text(
            editing ? 'ルートを更新しました。ルート一覧で確認できます。' : 'ルートを登録しました。ルート一覧で確認できます。',
          ),
          findsOneWidget,
        );
        expect(results, isEmpty);
        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();
        expect(find.text('保存完了'), findsOneWidget);
        await tester.tap(find.text('ルート一覧へ'));
        await tester.pumpAndSettle();
        expect(results, [true]);
        expect(find.text('一覧から開く'), findsOneWidget);
        expect(repository.saves, 1);
      },
    );
  }

  testWidgets(
    'cancel retains input, performs no save and can reopen confirmation',
    (tester) async {
      final repository = _Routes();
      await _open(tester, repository);
      await tester.tap(find.text('確定して保存'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('戻る'));
      await tester.pumpAndSettle();
      expect(repository.saves, 0);
      expect(find.text('保存完了'), findsNothing);
      expect(
        tester.widget<TextField>(_field('ルート名')).controller!.text,
        '保存するルート',
      );
      expect(tester.widget<TextField>(_field('住所')).controller!.text, '保存する住所');
      await tester.tap(find.text('確定して保存'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(repository.saves, 0);
    },
  );

  testWidgets(
    'failure never shows success or leaves the editor, and retains input',
    (tester) async {
      final repository = _Routes();
      final results = <bool?>[];
      await _open(tester, repository, result: results.add);
      await _confirm(tester);
      repository.response.completeError(StateError('Synthetic save failure'));
      await tester.pumpAndSettle();
      expect(find.text('保存完了'), findsNothing);
      expect(find.text('ルート一覧へ'), findsNothing);
      expect(find.textContaining('ルートを保存できませんでした'), findsOneWidget);
      expect(results, isEmpty);
      expect(repository.saves, 1);
      expect(
        tester.widget<TextField>(_field('ルート名')).controller!.text,
        '保存するルート',
      );
      expect(tester.widget<TextField>(_field('住所')).controller!.text, '保存する住所');
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '確定して保存'))
            .onPressed,
        isNotNull,
      );
    },
  );
}
