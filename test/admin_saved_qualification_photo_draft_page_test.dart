import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/qualifications/admin_saved_qualification_photo_contract.dart';
import 'package:sk_works/features/qualifications/admin_saved_qualification_photo_draft_page.dart';

const _company = '11111111-1111-1111-1111-111111111111';
const _actor = '22222222-2222-2222-2222-222222222222';
const _target = '33333333-3333-3333-3333-333333333333';
const _paths = ['front.jpg', 'back.jpg', 'extra.jpg'];
AdminSavedQualificationPhotoCapability _cap() =>
    AdminSavedQualificationPhotoCapability.parse(
      {
        'version': 1,
        'contract': 'qualification_admin_saved_photos',
        'company_id': _company,
        'actor_id': _actor,
        'photo_submission_available': true,
        'photo_upload_allowed': false,
        'max_photos': 20,
        'self_approval_allowed': false,
      },
      companyId: _company,
      actorId: _actor,
    );
ValueNotifier<AdminSavedQualificationPhotoScope> _scope() => ValueNotifier(
  const AdminSavedQualificationPhotoScope(companyId: _company, actorId: _actor),
);

Future<void> _open(
  WidgetTester tester, {
  required ValueNotifier<AdminSavedQualificationPhotoScope> scope,
  List<String> baseline = _paths,
  List<String>? selection,
  String target = _target,
  AdminSavedQualificationPhotoCapability? capability,
  ValueChanged<AdminSavedQualificationPhotoDraft?>? result,
}) async {
  await tester.binding.setSurfaceSize(const Size(600, 650));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              final draft = await Navigator.of(context)
                  .push<AdminSavedQualificationPhotoDraft>(
                    MaterialPageRoute(
                      builder: (_) => AdminSavedQualificationPhotoDraftPage(
                        capability: capability ?? _cap(),
                        companyId: _company,
                        actorId: _actor,
                        targetId: target,
                        savedPaths: baseline,
                        initialSelection: selection,
                        scope: scope,
                        photoBuilder: (_, path) => Text('saved-image:$path'),
                      ),
                    ),
                  );
              result?.call(draft);
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

void main() {
  testWidgets(
    'reorders saved photos and returns immutable local selection only',
    (tester) async {
      final scope = _scope();
      AdminSavedQualificationPhotoDraft? result;
      await _open(tester, scope: scope, result: (value) => result = value);
      await tester.tap(find.byTooltip('写真 1 を下へ'));
      await tester.pump();
      expect(
        tester.getTopLeft(find.text('saved-image:back.jpg')).dy,
        lessThan(tester.getTopLeft(find.text('saved-image:front.jpg')).dy),
      );
      await tester.tap(find.text('選択を確認'));
      await tester.pumpAndSettle();
      expect(result!.selectedPaths, ['back.jpg', 'front.jpg', 'extra.jpg']);
      expect(result!.savedPaths, _paths);
      expect(result!.targetId, _target);
      expect(
        () => result!.selectedPaths.add('new.jpg'),
        throwsUnsupportedError,
      );
    },
  );

  testWidgets(
    'all removal is local; restore and cancel keep original selection',
    (tester) async {
      final scope = _scope();
      final results = <AdminSavedQualificationPhotoDraft?>[];
      await _open(tester, scope: scope, result: results.add);
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('選択から外す').first);
        await tester.pump();
      }
      expect(find.textContaining('すべての写真を'), findsOneWidget);
      await tester.tap(find.text('元の選択に戻す'));
      await tester.pump();
      expect(find.text('saved-image:front.jpg'), findsOneWidget);
      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();
      expect(results, [null]);
      expect(_paths, ['front.jpg', 'back.jpg', 'extra.jpg']);
    },
  );

  testWidgets(
    'empty final photo_slots is permitted without deleting stored photos',
    (tester) async {
      AdminSavedQualificationPhotoDraft? result;
      await _open(
        tester,
        scope: _scope(),
        selection: [],
        result: (value) => result = value,
      );
      await tester.tap(find.text('選択を確認'));
      await tester.pumpAndSettle();
      expect(result!.selectedPaths, isEmpty);
      expect(result!.savedPaths, _paths);
    },
  );

  for (final invalid in <String, List<String>>{
    'unknown': ['unknown.jpg'],
    'duplicates': ['front.jpg', 'front.jpg'],
    'empty path': [''],
    'whitespace': ['  '],
    'over limit': List.generate(21, (i) => 'image$i.jpg'),
  }.entries) {
    testWidgets('rejects ${invalid.key} initial selection', (tester) async {
      await _open(tester, scope: _scope(), selection: invalid.value);
      expect(find.textContaining('開き直してください'), findsOneWidget);
      expect(find.text('saved-image:front.jpg'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '選択を確認'))
            .onPressed,
        isNull,
      );
    });
  }

  for (final baseline in <List<String>>[
    [],
    ['front.jpg', 'front.jpg'],
    [''],
    List.generate(21, (i) => 'image$i.jpg'),
  ]) {
    testWidgets('rejects invalid trusted baseline $baseline', (tester) async {
      await _open(tester, scope: _scope(), baseline: baseline);
      expect(find.textContaining('開き直してください'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_downward), findsNothing);
    });
  }

  for (final changed in [
    const AdminSavedQualificationPhotoScope(
      companyId: _company,
      actorId: 'another',
    ),
    const AdminSavedQualificationPhotoScope(
      companyId: 'another',
      actorId: _actor,
    ),
    const AdminSavedQualificationPhotoScope(),
  ]) {
    testWidgets(
      'scope change clears photos and remains revoked after return: ${changed.actorId}/${changed.companyId}',
      (tester) async {
        final scope = _scope();
        await _open(tester, scope: scope);
        scope.value = changed;
        scope.value = const AdminSavedQualificationPhotoScope(
          companyId: _company,
          actorId: _actor,
        );
        await tester.pump();
        expect(find.text('saved-image:front.jpg'), findsNothing);
        expect(find.textContaining('開き直してください'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, '選択を確認'))
              .onPressed,
          isNull,
        );
      },
    );
  }

  testWidgets(
    'unavailable capability or malformed target never displays saved images',
    (tester) async {
      await _open(
        tester,
        scope: _scope(),
        capability: AdminSavedQualificationPhotoCapability.unavailable,
      );
      expect(find.textContaining('開き直してください'), findsOneWidget);
      await _open(tester, scope: _scope(), target: 'not-a-uuid');
      expect(find.text('saved-image:front.jpg'), findsNothing);
    },
  );

  testWidgets(
    'mutated baseline is refused at confirmation without returning a draft',
    (tester) async {
      final baseline = List.of(_paths);
      final results = <AdminSavedQualificationPhotoDraft?>[];
      await _open(
        tester,
        scope: _scope(),
        baseline: baseline,
        result: results.add,
      );
      baseline.add('unseen.jpg');
      await tester.tap(find.text('選択を確認'));
      await tester.pump();
      expect(results, isEmpty);
      expect(find.textContaining('開き直してください'), findsOneWidget);
    },
  );

  testWidgets('footer remains visible while photos scroll', (tester) async {
    await _open(tester, scope: _scope());
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.text('選択を確認').hitTestable(), findsOneWidget);
    expect(find.text('キャンセル').hitTestable(), findsOneWidget);
  });
}
