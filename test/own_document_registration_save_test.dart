import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sk_works/features/people/own_document_registration_page.dart';
import 'package:sk_works/features/people/worker_document_photos.dart';

class _MemoryPhoto extends XFile {
  _MemoryPhoto(this.bytes) : super('license.jpg');
  final List<int> bytes;

  @override
  String get name => 'license.jpg';

  @override
  Future<Uint8List> readAsBytes() async => Uint8List.fromList(bytes);
}

class _UnreadablePhoto extends XFile {
  _UnreadablePhoto() : super('license.jpg');

  @override
  Future<Uint8List> readAsBytes() async =>
      throw const FileSystemException('synthetic read failure');
}

class _Gateway implements OwnDocumentRegistrationGateway {
  _Gateway({this.statuses = const []});
  final List<Map<String, dynamic>> statuses;
  final calls = <({String requirement, Uint8List? bytes, String? filename})>[];
  Future<void> Function()? onSave;

  @override
  Future<Map<String, List<Map<String, dynamic>>>> loadAll() async => {
    'workers': [
      {'id': 'worker', 'name': '本人'},
    ],
    'requirements': [
      {'id': 'license', 'name': '運転免許証', 'scope': 'internal'},
    ],
    'statuses': statuses,
  };

  @override
  Future<void> saveOwnDocument({
    required String requirementId,
    DateTime? expiresAt,
    required String notes,
    Uint8List? attachmentBytes,
    String? originalFilename,
    bool requireEmptyAttachment = false,
  }) async {
    calls.add((
      requirement: requirementId,
      bytes: attachmentBytes,
      filename: originalFilename,
    ));
    final save = onSave;
    if (save != null) await save();
  }
}

class _PhotosGateway extends _Gateway implements OwnDocumentPhotoGateway {
  _PhotosGateway({
    this.editingAvailable = true,
    List<Map<String, dynamic>>? statuses,
  }) : super(
         statuses:
             statuses ??
             [
               {
                 'id': 'status',
                 'requirement_id': 'license',
                 'status': 'submitted',
                 'attachment_path': 'front.pdf',
                 'attachment_paths': ['front.pdf', 'back.pdf', 'extra.pdf'],
               },
             ],
       );
  final edits = <List<WorkerDocumentPhoto>>[];
  final bool editingAvailable;
  @override
  bool get photoEditingAvailable => editingAvailable;
  @override
  Future<String> signedUrl(String path) async => 'https://example.test/$path';
  @override
  Future<void> editPhotos(
    Map<String, dynamic> row,
    List<WorkerDocumentPhoto> photos,
  ) async {
    edits.add(photos);
  }

  @override
  Future<void> savePhotos({
    required String requirementId,
    DateTime? expiresAt,
    required String notes,
    required List<WorkerDocumentPhoto> photos,
    required List<String> expectedPaths,
  }) async {
    edits.add(photos);
  }
}

Future<void> _open(
  WidgetTester tester,
  _Gateway gateway,
  Future<XFile?> Function(ImageSource)? picker,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: OwnDocumentRegistrationPage(gateway: gateway, pickPhoto: picker),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byType(FloatingActionButton));
  await tester.pumpAndSettle();
}

Future<void> _selectPhoto(WidgetTester tester) async {
  await tester.tap(find.byType(CheckboxListTile));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, '登録'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'unregistered row opens that document registration with legacy photo option',
    (tester) async {
      final gateway = _PhotosGateway(editingAvailable: false, statuses: []);
      await tester.pumpWidget(
        MaterialApp(
          home: OwnDocumentRegistrationPage(
            gateway: gateway,
            pickPhoto: (_) async => _MemoryPhoto([1, 2, 3]),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('登録する'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CheckboxListTile>(find.byType(CheckboxListTile))
            .onChanged,
        isNotNull,
      );
      await _selectPhoto(tester);
      await tester.tap(find.text('写真から選ぶ'));
      await tester.pumpAndSettle();
      expect(gateway.calls.single.bytes, Uint8List.fromList([1, 2, 3]));
      expect(gateway.edits, isEmpty);
    },
  );
  testWidgets(
    'pending schema keeps existing photos readable and editing disabled',
    (tester) async {
      final gateway = _PhotosGateway(editingAvailable: false);
      await tester.pumpWidget(
        MaterialApp(home: OwnDocumentRegistrationPage(gateway: gateway)),
      );
      await tester.pumpAndSettle();
      expect(find.text('提出済み / 画像あり（3枚）'), findsOneWidget);
      await tester.tap(find.text('運転免許証'));
      await tester.pumpAndSettle();
      expect(find.text('複数写真の保存準備中です。保存済みの写真は確認できます。'), findsOneWidget);
      expect(find.text('写真を確定'), findsNothing);
      expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '1枚撮影'))
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('閉じる'));
      await tester.pumpAndSettle();
      expect(gateway.edits, isEmpty);
      expect(gateway.calls, isEmpty);
    },
  );

  testWidgets(
    'saved multi-photo list opens editor and cancellation makes no write',
    (tester) async {
      final gateway = _PhotosGateway();
      await tester.pumpWidget(
        MaterialApp(home: OwnDocumentRegistrationPage(gateway: gateway)),
      );
      await tester.pumpAndSettle();
      expect(find.text('提出済み / 画像あり（3枚）'), findsOneWidget);
      await tester.tap(find.text('運転免許証'));
      await tester.pumpAndSettle();
      expect(find.text('登録写真 3枚'), findsOneWidget);
      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();
      expect(gateway.edits, isEmpty);
    },
  );

  testWidgets(
    'removing one saved photo submits the remaining ordered draft once',
    (tester) async {
      final gateway = _PhotosGateway();
      await tester.pumpWidget(
        MaterialApp(home: OwnDocumentRegistrationPage(gateway: gateway)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('運転免許証'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('写真を一覧から削除').at(1));
      await tester.pumpAndSettle();
      expect(find.text('登録写真 2枚'), findsOneWidget);
      await tester.tap(find.text('写真を確定'));
      await tester.pumpAndSettle();
      expect(gateway.edits, hasLength(1));
      expect(gateway.edits.single.map((photo) => photo.path), [
        'front.pdf',
        'extra.pdf',
      ]);
      expect(gateway.calls, isEmpty);
    },
  );

  testWidgets(
    'submitted metadata without attachment stays submitted and shows no photo',
    (tester) async {
      final gateway = _Gateway(
        statuses: [
          {
            'id': 'status',
            'requirement_id': 'license',
            'status': 'submitted',
            'attachment_path': null,
          },
        ],
      );
      await tester.pumpWidget(
        MaterialApp(home: OwnDocumentRegistrationPage(gateway: gateway)),
      );
      await tester.pumpAndSettle();
      expect(find.text('提出済み / 写真未添付'), findsOneWidget);
      expect(find.text('未登録'), findsNothing);
      expect(gateway.calls, isEmpty);
    },
  );

  testWidgets(
    'source selection cancellation performs no save or success message',
    (tester) async {
      final gateway = _Gateway();
      var picked = false;
      await _open(tester, gateway, (_) async {
        picked = true;
        return null;
      });
      await _selectPhoto(tester);
      expect(gateway.calls, isEmpty);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(picked, isFalse);
      expect(gateway.calls, isEmpty);
      expect(find.text('自分の書類を登録しました'), findsNothing);
    },
  );

  testWidgets('camera cancellation performs no save or success message', (
    tester,
  ) async {
    final gateway = _Gateway();
    await _open(tester, gateway, (_) async => null);
    await _selectPhoto(tester);
    await tester.tap(find.text('カメラで撮影'));
    await tester.pumpAndSettle();
    expect(gateway.calls, isEmpty);
    expect(find.text('自分の書類を登録しました'), findsNothing);
  });

  testWidgets('photo bytes are ready before a single save call', (
    tester,
  ) async {
    final gateway = _Gateway();
    final photo = Completer<XFile?>();
    await _open(tester, gateway, (_) => photo.future);
    await _selectPhoto(tester);
    await tester.tap(find.text('写真から選ぶ'));
    await tester.pump();
    expect(gateway.calls, isEmpty);
    photo.complete(_MemoryPhoto([1, 2, 3]));
    await tester.pumpAndSettle();
    expect(gateway.calls, hasLength(1));
    expect(gateway.calls.single.requirement, 'license');
    expect(gateway.calls.single.bytes, orderedEquals([1, 2, 3]));
    expect(gateway.calls.single.filename, 'license.jpg');
    expect(find.text('自分の書類を登録しました'), findsOneWidget);
  });

  testWidgets('picker failure never reaches save', (tester) async {
    final gateway = _Gateway();
    await _open(
      tester,
      gateway,
      (_) async => throw StateError('camera unavailable'),
    );
    await _selectPhoto(tester);
    await tester.tap(find.text('カメラで撮影'));
    await tester.pumpAndSettle();
    expect(gateway.calls, isEmpty);
    expect(find.text('自分の書類を登録しました'), findsNothing);
    expect(find.textContaining('書類を登録できませんでした'), findsOneWidget);
  });

  testWidgets('photo byte read failure never reaches save', (tester) async {
    final gateway = _Gateway();
    await _open(tester, gateway, (_) async => _UnreadablePhoto());
    await _selectPhoto(tester);
    await tester.tap(find.text('写真から選ぶ'));
    await tester.pumpAndSettle();
    expect(gateway.calls, isEmpty);
    expect(find.text('自分の書類を登録しました'), findsNothing);
    expect(find.textContaining('書類を登録できませんでした'), findsOneWidget);
  });

  testWidgets('upload failure or unknown save result never reports success', (
    tester,
  ) async {
    for (final error in [
      StateError('Storage 403'),
      StateError('response unknown'),
    ]) {
      final gateway = _Gateway()..onSave = () async => throw error;
      await _open(tester, gateway, (_) async => _MemoryPhoto([1]));
      await _selectPhoto(tester);
      await tester.tap(find.text('写真から選ぶ'));
      await tester.pumpAndSettle();
      expect(gateway.calls, hasLength(1));
      expect(find.text('自分の書類を登録しました'), findsNothing);
      expect(find.textContaining('書類を登録できませんでした'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets(
    'metadata-only save waits for confirmation and prevents duplicate tap',
    (tester) async {
      final saved = Completer<void>();
      final gateway = _Gateway()..onSave = () => saved.future;
      await _open(
        tester,
        gateway,
        (_) async => throw StateError('unexpected picker'),
      );
      await tester.tap(find.widgetWithText(FilledButton, '登録'));
      await tester.pumpAndSettle();
      expect(gateway.calls, hasLength(1));
      expect(gateway.calls.single.bytes, isNull);
      expect(find.text('自分の書類を登録しました'), findsNothing);
      expect(
        tester
            .widget<FloatingActionButton>(find.byType(FloatingActionButton))
            .onPressed,
        isNull,
      );
      saved.complete();
      await tester.pumpAndSettle();
      expect(find.text('自分の書類を登録しました'), findsOneWidget);
    },
  );

  testWidgets('leaving page while picking does not save later', (tester) async {
    final gateway = _Gateway();
    final photo = Completer<XFile?>();
    await _open(tester, gateway, (_) => photo.future);
    await _selectPhoto(tester);
    await tester.tap(find.text('写真から選ぶ'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    photo.complete(_MemoryPhoto([1]));
    await tester.pump();
    expect(gateway.calls, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
