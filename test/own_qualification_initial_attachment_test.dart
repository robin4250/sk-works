import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/people/worker_document_photos.dart';
import 'package:sk_works/features/qualifications/own_qualification_photo_contract.dart';
import 'package:sk_works/features/qualifications/own_qualification_photo_submission_repository.dart';
import 'package:sk_works/features/qualifications/own_qualification_registration_page.dart';
import 'package:sk_works/features/qualifications/qualification_cloud_repository.dart';

class FakeCloud implements QualificationCloudRepository {
  int inserts = 0;
  @override String? get currentUserId => 'owner';
  @override Future<Map<String, dynamic>> loadOwnQualificationWorkspace() async => {
    'worker': {'id':'worker', 'name':'本人'},
    'masters': [{'id':'master','name':'資格A','is_active':true}],
    'qualifications': <Map<String,dynamic>>[],
  };
  @override Future<Map<String, dynamic>> insertOwnQualification({
    required String qualificationMasterId, String? certificateNumber,
    DateTime? issuedAt, DateTime? expiresAt, String? issuer, String? notes,
  }) async {
    inserts++;
    return {'id':'qualification', 'worker_id':'worker', 'qualification_master_id':qualificationMasterId};
  }
  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class FakePhoto implements OwnQualificationPhotoSubmissionRepository {
  bool fail = false;
  bool upload = true;
  int submits = 0;
  List<WorkerDocumentPhoto>? sent;
  @override String? get actor => 'owner';
  @override Future<OwnQualificationPhotoCapability> capability() async =>
      OwnQualificationPhotoCapability(available:true, uploadAllowed:upload, maxPhotos:20);
  @override Future<Map<String,dynamic>?> pending() async => null;
  @override Future<List<Map<String,dynamic>>> submissions() async => [];
  @override Future<OwnQualificationPreparedPhotos> submitSelection({
    required Map<String,dynamic> row, required List<WorkerDocumentPhoto> photos,
  }) async {
    submits++; sent = photos;
    if (fail) throw StateError('送信結果不明');
    return const OwnQualificationPreparedPhotos(
      id:'request',targetId:'qualification',paths:[],uploads:{},status:'pending');
  }
  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<void> start(WidgetTester tester, FakeCloud cloud, FakePhoto photo) async {
    await tester.pumpWidget(MaterialApp(home: OwnQualificationRegistrationPage(
      repository: cloud, photoRepository: photo,
      pickAttachments: (_, __) async => [
        WorkerDocumentPhoto.pending(Uint8List.fromList([37,80,68,70]), 'license.pdf'),
      ],
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('資格を登録').last);
    await tester.pumpAndSettle();
  }
  testWidgets('資格情報の初回登録後に選択したPDFを承認申請する', (tester) async {
    final cloud = FakeCloud(); final photo = FakePhoto();
    await start(tester, cloud, photo);
    await tester.ensureVisible(find.text('資格証を選択（0件）'));
    await tester.tap(find.text('資格証を選択（0件）'));
    await tester.pumpAndSettle();
    expect(find.text('資格証を選択（1件）'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.widgetWithText(FilledButton, '登録')).last);
    await tester.pumpAndSettle();
    expect(cloud.inserts, 1);
    expect(photo.submits, 1);
    expect(photo.sent!.single.filename, 'license.pdf');
    expect(find.text('資格情報を登録し、資格証を申請しました。'), findsOneWidget);
  });
  testWidgets('送信結果不明は資格登録を繰り返さず確認を案内する', (tester) async {
    final cloud = FakeCloud(); final photo = FakePhoto()..fail = true;
    await start(tester, cloud, photo);
    await tester.ensureVisible(find.text('資格証を選択（0件）'));
    await tester.tap(find.text('資格証を選択（0件）'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.widgetWithText(FilledButton, '登録')).last);
    await tester.pumpAndSettle();
    expect(cloud.inserts, 1); expect(photo.submits, 1);
    expect(find.text('資格情報は登録済みです。資格証の申請結果を一覧で確認してください。'), findsOneWidget);
  });
  testWidgets('写真の送信停止中は初回添付を選べない', (tester) async {
    final cloud = FakeCloud(); final photo = FakePhoto()..upload = false;
    await start(tester, cloud, photo);
    final button = tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '資格証を選択（0件）'));
    expect(button.onPressed, isNull);
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.widgetWithText(FilledButton, '登録')).last);
    await tester.pumpAndSettle();
    expect(cloud.inserts, 1); expect(photo.submits, 0);
  });
}
