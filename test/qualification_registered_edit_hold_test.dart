import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/qualifications/qualification_certificate_page.dart';
import 'package:sk_works/features/qualifications/qualification_certificate_repository.dart';
import 'package:sk_works/features/qualifications/qualification_cloud_page.dart';
import 'package:sk_works/features/qualifications/qualification_cloud_repository.dart';
import 'package:sk_works/international/language_controller.dart';
import 'package:sk_works/international/language_pack_registry.dart';

Map<String, dynamic> _saved({bool photos = true}) => {
  'id': 'saved',
  'worker_id': 'worker',
  'qualification_master_id': 'master',
  'certificate_number': 'SAVED-CERT',
  'expires_at': '2030-01-01',
  'attachment_path': photos ? 'front.jpg' : null,
  'attachment_back_path': photos ? 'back.jpg' : null,
  'attachment_extra_paths': photos ? ['extra.jpg'] : <String>[],
};
Map<String, dynamic> _data(List<Map<String, dynamic>> rows) => {
  'masters': [
    {'id': 'master', 'name': 'Existing qualification'},
  ],
  'workers': [
    {'id': 'worker', 'name': 'Existing worker'},
  ],
  'qualifications': rows,
  'supports_extra_photos': true,
};

class _Photos implements QualificationCertificateRepository {
  _Photos({this.photos = true});
  final bool photos;
  final signed = <String>[];
  final writes = <Symbol>[];
  @override
  String? get currentUserId => 'actor';
  @override
  Stream<AuthState> get authChanges => const Stream.empty();
  @override
  Future<bool> canManageCertificates() async => true;
  @override
  Future<Map<String, dynamic>> loadAll() async =>
      _data([_saved(photos: photos)]);
  @override
  Future<String> createSignedUrl(String path) async {
    signed.add(path);
    throw StateError('Synthetic unavailable image');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    writes.add(invocation.memberName);
    throw StateError('No direct mutation may be called');
  }
}

class _Cloud implements QualificationCloudRepository {
  _Cloud({this.hasSaved = true});
  final bool hasSaved;
  final inserts = <Map<String, Object?>>[];
  final writes = <Symbol>[];
  @override
  Future<Map<String, dynamic>> loadAll() async =>
      _data(hasSaved ? [_saved(photos: false)] : []);
  @override
  Future<bool> canManageMaster() async => true;
  @override
  Future<bool> canManageWorkerQualifications() async => true;
  @override
  Future<Map<String, dynamic>> insertWorkerQualification({
    required String workerId,
    required String qualificationMasterId,
    String? certificateNumber,
    DateTime? issuedAt,
    DateTime? expiresAt,
    String? issuer,
    String? notes,
    String? attachmentPath,
  }) async {
    inserts.add({
      'worker_id': workerId,
      'qualification_master_id': qualificationMasterId,
      'certificate_number': certificateNumber,
      'attachment_path': attachmentPath,
    });
    return {
      ..._saved(photos: false),
      'id': 'new',
      'certificate_number': certificateNumber,
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    writes.add(invocation.memberName);
    throw StateError('Existing rows must not be mutated');
  }
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

void main() {
  setUp(
    () => SkoLanguageController.pack.value = LanguagePackRegistry.resolve('ja'),
  );
  tearDown(
    () => SkoLanguageController.pack.value = LanguagePackRegistry.resolve('ja'),
  );

  for (final photos in [false, true]) {
    testWidgets(
      'saved certificate photos=$photos remains viewable without direct edit actions',
      (tester) async {
        final repository = _Photos(photos: photos);
        await tester.pumpWidget(
          MaterialApp(
            home: QualificationCertificatePage(repository: repository),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Existing qualification'));
        await tester.pumpAndSettle();
        expect(find.text(registeredQualificationChangeNotice), findsOneWidget);
        expect(find.text('表面'), findsOneWidget);
        expect(find.text('裏面（ない場合は登録不要）'), findsOneWidget);
        for (final label in [
          'カメラで撮影',
          '撮り直す',
          '写真から選ぶ',
          '写真から差し替える',
          'この面の画像を削除',
          '追加写真を選ぶ（複数可）',
          '追加写真を撮影',
        ]) {
          expect(find.text(label), findsNothing);
        }
        if (photos) {
          expect(repository.signed.toSet(), {
            'front.jpg',
            'back.jpg',
            'extra.jpg',
          });
          expect(find.text('追加写真 3'), findsOneWidget);
        } else {
          expect(repository.signed, isEmpty);
        }
        expect(repository.writes, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'registered cloud entry explains approval hold and cannot delete',
    (tester) async {
      final repository = _Cloud();
      final photos = _Photos(photos: false);
      await tester.pumpWidget(
        MaterialApp(
          home: QualificationCloudPage(
            repository: repository,
            certificateRepository: photos,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('確認・編集'), findsNothing);
      await tester.tap(find.text('詳細を確認').first);
      await tester.pumpAndSettle();
      expect(find.text('資格証を確認'), findsOneWidget);
      expect(find.text('資格登録を削除'), findsNothing);
      await tester.ensureVisible(find.text('登録後の変更について'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('登録後の変更について'));
      await tester.pumpAndSettle();
      expect(find.text(registeredQualificationChangeNotice), findsOneWidget);
      expect(repository.writes, isEmpty);
      expect(photos.writes, isEmpty);
      expect(repository.inserts, isEmpty);
    },
  );

  testWidgets(
    'initial metadata registration still inserts once with the entered values',
    (tester) async {
      final repository = _Cloud(hasSaved: false);
      final photos = _Photos(photos: false);
      await tester.pumpWidget(
        MaterialApp(
          home: QualificationCloudPage(
            repository: repository,
            certificateRepository: photos,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('資格を登録'));
      await tester.pumpAndSettle();
      await tester.enterText(_field('証明書番号'), 'INITIAL-123');
      await tester.tap(find.widgetWithText(FilledButton, '登録'));
      await tester.pumpAndSettle();
      expect(repository.inserts, [
        {
          'worker_id': 'worker',
          'qualification_master_id': 'master',
          'certificate_number': 'INITIAL-123',
          'attachment_path': null,
        },
      ]);
      expect(repository.writes, isEmpty);
      expect(photos.writes, isEmpty);
      expect(find.text('資格をクラウドに登録しました'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('approval hold has an English explanation', (tester) async {
    SkoLanguageController.pack.value = LanguagePackRegistry.resolve('en');
    await tester.pumpWidget(
      MaterialApp(
        home: QualificationCertificatePage(repository: _Photos(photos: false)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Existing qualification'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Changes after registration require approval. Editing is unavailable until change requests are ready.',
      ),
      findsOneWidget,
    );
  });
}
