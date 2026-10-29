import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sk_works/features/people/own_document_registration_page.dart';
import 'package:sk_works/features/people/worker_document_photos.dart';
import 'package:sk_works/features/people/worker_document_change_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sk_works/features/common/data_date_labels.dart';
import 'package:sk_works/features/shared/resource_registration_card.dart';

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
  _Gateway({
    this.statuses = const [],
    this.scope = 'internal',
    this.visible = true,
  });
  final bool visible;
  final String scope;
  final List<Map<String, dynamic>> statuses;
  final calls = <({String requirement, Uint8List? bytes, String? filename})>[];
  Future<void> Function()? onSave;

  @override
  Future<Map<String, List<Map<String, dynamic>>>> loadAll() async => {
    'workers': [
      {'id': 'worker', 'name': '本人'},
    ],
    'requirements': [
      {'id': 'license', 'name': '運転免許証', 'scope': scope, 'is_active': visible},
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
  await tester.tap(find.widgetWithText(FilledButton, '書類を登録'));
  await tester.pumpAndSettle();
}

Future<void> _selectPhoto(WidgetTester tester) async {
  await tester.ensureVisible(find.byType(CheckboxListTile));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(CheckboxListTile));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, '登録').last);
  await tester.pumpAndSettle();
}

String _changeId(int n) =>
    '10000000-0000-0000-0000-${n.toString().padLeft(12, '0')}';

class _ChangeGateway extends _PhotosGateway
    implements OwnDocumentChangeGateway {
  _ChangeGateway(this.rpc, {this.requiredDocument=false});
  final bool requiredDocument;
  final Future<Object?> Function(String, Map<String, dynamic>) rpc;
  final events = StreamController<void>.broadcast(sync: true);
  String actor = _changeId(6);
  Future<String> Function()? companyLoad;
  @override
  String? get actorId => actor;
  @override
  bool get isCurrentActor => true;
  @override
  Future<String> changeCompanyId() =>
      companyLoad?.call() ?? Future.value(_changeId(3));
  @override
  WorkerDocumentChangeRepository createChangeRepository() =>
      WorkerDocumentChangeRepository.forTesting(
        actor: () => actor,
        changes: events.stream,
        rpc: rpc,
      );
  @override
  Future<Map<String, List<Map<String, dynamic>>>> loadAll() async => {
    'workers': [
      {'id': _changeId(4), 'name': '本人'},
    ],
    'requirements': [
      {
        'id': _changeId(5),
        'name': '運転免許証',
        'scope': 'internal',
        'is_active': true,
        'is_required': requiredDocument,
      },
    ],
    'statuses': [
      {
        'id': _changeId(2),
        'worker_id': _changeId(4),
        'requirement_id': _changeId(5),
        'status': 'submitted',
        'notes': 'existing',
        'updated_at': '2026-10-18T00:00:00Z',
      },
    ],
  };
}

void main() {
  testWidgets(
    'registered own entry opens approval flow; unavailable API never calls old save',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final actions = <String>[];
      final gateway = _ChangeGateway((action, data) async {
        actions.add(action);
        return {
          'version': 1,
          'change_requests_available': false,
          'new_upload_available': false,
          'max_photos': 20,
          'self_approval_allowed': false,
        };
      });
      await tester.pumpWidget(
        MaterialApp(home: OwnDocumentRegistrationPage(gateway: gateway)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, '確認・編集'));
      await tester.pumpAndSettle();
      expect(find.text('書類の変更申請'), findsOneWidget);
      expect(find.textContaining('準備中です。正式な書類は変更していません'), findsOneWidget);
      expect(actions, ['capability']);
      expect(gateway.calls, isEmpty);
      expect(gateway.edits, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => gateway.events.close());
    },
  );
  testWidgets('partial saved required metadata opens existing edit approval without direct overwrite', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final actions=<String>[];Map<String,dynamic>? prepared;
    Map<String,dynamic> receipt(String state)=>{
      'version':1,'id':prepared!['request_id'],'target_id':_changeId(2),
      'company_id':_changeId(3),'worker_id':_changeId(4),'requirement_id':_changeId(5),
      'requested_by':_changeId(6),'status':state,'can_review':false,
      'previous':{'id':_changeId(2),'company_id':_changeId(3),'worker_id':_changeId(4),
        'requirement_id':_changeId(5),'updated_at':'2026-10-18T00:00:00Z'},
      'proposed':prepared!['proposed'],
    };
    final gateway=_ChangeGateway((action,data) async {
      actions.add(action);
      if(action=='capability')return {'version':1,'change_requests_available':true,
        'new_upload_available':false,'max_photos':20,'self_approval_allowed':false};
      if(action=='prepare'){prepared=Map<String,dynamic>.from(data);return receipt('draft');}
      if(action=='submit'){expect(data['request_id'],prepared!['request_id']);return receipt('pending');}
      throw StateError('Unexpected synthetic action');
    },requiredDocument:true);
    final original=Map<String,dynamic>.from((await gateway.loadAll())['statuses']!.single);
    await tester.pumpWidget(MaterialApp(home:OwnDocumentRegistrationPage(gateway:gateway)));
    await tester.pumpAndSettle();
    expect(find.text('添付待ち'),findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton,'登録').first);await tester.pumpAndSettle();
    expect(find.text('書類の変更申請'),findsOneWidget);
    expect(tester.widget<TextField>(find.widgetWithText(TextField,'備考')).controller!.text,'existing');
    await tester.enterText(find.widgetWithText(TextField,'備考'),'synthetic revised note');
    await tester.tap(find.text('変更を申請'));await tester.pumpAndSettle();
    expect(actions,['capability','prepare','submit']);
    expect((prepared!['proposed'] as Map)['notes'],'synthetic revised note');
    expect((prepared!['proposed'] as Map)['attachment_paths'],isEmpty);
    expect(prepared!['expected_updated_at'],'2026-10-18T00:00:00Z');
    expect(find.textContaining('承認されるまで正式な書類は変わりません'),findsOneWidget);
    expect(gateway.calls,isEmpty);expect(gateway.edits,isEmpty);
    expect((await gateway.loadAll())['statuses']!.single,original);
    await tester.pumpWidget(const SizedBox());await tester.runAsync(()=>gateway.events.close());
  });
  testWidgets('actor ABA during membership lookup cannot enter change flow', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final pending = Completer<String>();
    final actions = <String>[];
    final gateway = _ChangeGateway((action, data) async {
      actions.add(action);
      throw StateError('must not run');
    })..companyLoad = () => pending.future;
    await tester.pumpWidget(
      MaterialApp(home: OwnDocumentRegistrationPage(gateway: gateway)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, '確認・編集'));
    await tester.pump();
    gateway.actor = _changeId(9);
    gateway.events.add(null);
    gateway.actor = _changeId(6);
    gateway.events.add(null);
    pending.complete(_changeId(3));
    await tester.pumpAndSettle();
    expect(find.text('書類の変更申請'), findsNothing);
    expect(actions, isEmpty);
    expect(gateway.calls, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => gateway.events.close());
  });

  testWidgets(
    'hidden requirements never appear in own registration or picker',
    (tester) async {
      final gateway = _Gateway(visible: false);
      await tester.pumpWidget(
        MaterialApp(home: OwnDocumentRegistrationPage(gateway: gateway)),
      );
      await tester.pumpAndSettle();
      expect(find.text('運転免許証'), findsNothing);
      expect(gateway.calls, isEmpty);
      final action = tester.widget<FilledButton>(
        find.byType(FilledButton).first,
      );
      expect(action.onPressed, isNull);
    },
  );

  testWidgets(
    'shared document has one registration and saves the same requirement once',
    (tester) async {
      final gateway = _Gateway(scope: 'both');
      await tester.pumpWidget(
        MaterialApp(home: OwnDocumentRegistrationPage(gateway: gateway)),
      );
      await tester.pumpAndSettle();
      expect(find.text('運転免許証'), findsOneWidget);
      expect(find.textContaining('自社・取引会社で共用（登録は1回）'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '登録').first, findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '登録').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '登録').last);
      await tester.pumpAndSettle();
      expect(gateway.calls, hasLength(1));
      expect(gateway.calls.single.requirement, 'license');
      expect(gateway.calls.single.bytes, isNull);
    },
  );

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
      await tester.tap(find.widgetWithText(FilledButton, '登録').first);
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
      expect(find.text('登録済み'), findsOneWidget);
      expect(find.textContaining('添付 3件（詳細で確認）'), findsOneWidget);
      await tester.tap(find.widgetWithText(OutlinedButton, '確認・編集'));
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

  testWidgets('saved multi-photo list without approval API stays read only', (
    tester,
  ) async {
    final gateway = _PhotosGateway();
    await tester.pumpWidget(
      MaterialApp(home: OwnDocumentRegistrationPage(gateway: gateway)),
    );
    await tester.pumpAndSettle();
    expect(find.text('登録済み'), findsOneWidget);
    expect(find.textContaining('添付 3件（詳細で確認）'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, '確認・編集'));
    await tester.pumpAndSettle();
    expect(find.text('登録写真 3枚'), findsOneWidget);
    await tester.tap(find.text('閉じる'));
    await tester.pumpAndSettle();
    expect(gateway.edits, isEmpty);
  });

  testWidgets(
    'registered photo changes never use the legacy direct edit gateway',
    (tester) async {
      final gateway = _PhotosGateway();
      await tester.pumpWidget(
        MaterialApp(home: OwnDocumentRegistrationPage(gateway: gateway)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, '確認・編集'));
      await tester.pumpAndSettle();
      for (final button in tester.widgetList<IconButton>(
        find.widgetWithIcon(IconButton, Icons.delete_outline),
      )) {
        expect(button.onPressed, isNull);
      }
      expect(find.text('写真を確定'), findsNothing);
      expect(gateway.edits, isEmpty);
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
            'created_at': '2026-10-01T12:00:00Z',
            'updated_at': '2026-10-01T12:00:00Z',
            'expires_at': '2026-11-30',
          },
        ],
      );
      await tester.pumpWidget(
        MaterialApp(home: OwnDocumentRegistrationPage(gateway: gateway)),
      );
      await tester.pumpAndSettle();
      expect(find.text('登録済み'), findsOneWidget);
      expect(find.text('登録なし'), findsOneWidget);
      expect(
        find.text(
          DataDateLabels.labels(createdAt: '2026-10-01T12:00:00Z').first,
        ),
        findsOneWidget,
      );
      expect(find.textContaining('期限 2026-11-30'), findsOneWidget);
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
      await tester.tap(find.widgetWithText(FilledButton, '登録').last);
      await tester.pumpAndSettle();
      expect(gateway.calls, hasLength(1));
      expect(gateway.calls.single.bytes, isNull);
      expect(find.text('自分の書類を登録しました'), findsNothing);
      expect(
        tester
            .widget<ResourceRegistrationFooter>(
              find.byType(ResourceRegistrationFooter),
            )
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
