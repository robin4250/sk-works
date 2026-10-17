import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/operations/vehicle_editor_page.dart';
import 'package:sk_works/features/operations/vehicle_route_repository.dart';

class _Repository implements VehicleRouteRepository {
  final ids = <String?>[];
  final notified = <String>[];
  bool failNotice = true;
  bool failBody = false;
  String? failUploadKind;
  final uploads = <({String vehicleId, String kind, String filename, String contentType, Uint8List bytes})>[];
  @override
  Future<void> uploadVehicleDocument({
    required String vehicleId,
    required String kind,
    required Uint8List bytes,
    required String filename,
    required String contentType,
  }) async {
    uploads.add((vehicleId: vehicleId, kind: kind, filename: filename, contentType: contentType,
        bytes: Uint8List.fromList(bytes)));
    if (kind == failUploadKind) throw StateError('synthetic upload failure');
  }
  @override
  Future<String> saveVehicle({
    String? id,
    required String name,
    required String registrationNumber,
    required double odometerKm,
    required String storageAddress,
  }) async {
    ids.add(id);
    if (failBody) throw StateError('offline');
    return id ?? 'saved-exact-vehicle';
  }
  @override
  Future<List<String>> notifyMissingVehicleDocuments(String id) async {
    notified.add(id);
    if (failNotice) throw StateError('notice offline');
    return ['車検証'];
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _open(WidgetTester tester, _Repository repository) async {
  tester.view.physicalSize = const Size(1000, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: VehicleEditorPage(
    repository: repository,
  )));
  await tester.enterText(find.byType(TextField).at(0), '作業車');
  await tester.enterText(find.byType(TextField).at(1), '品川123');
  await tester.enterText(find.byType(TextField).at(2), '1234');
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.text('確定して保存'));
  await tester.pumpAndSettle();
  await tester.tap(find.descendant(of: find.byType(AlertDialog),
    matching: find.text('確定して保存')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('notification failure retains returned exact ID for retry',
      (tester) async {
    final repository = _Repository();
    await _open(tester, repository);
    await _save(tester);
    expect(repository.ids, [null]);
    expect(find.textContaining('車両本体は保存済みです。'), findsWidgets);
    expect(find.text('保存完了'), findsNothing);
    expect(find.text('作業車'), findsOneWidget);
    repository.failNotice = false;
    await _save(tester);
    expect(repository.ids, [null, 'saved-exact-vehicle']);
    expect(repository.notified,
      ['saved-exact-vehicle', 'saved-exact-vehicle']);
    expect(find.text('保存完了'), findsOneWidget);
    expect(find.textContaining('未登録書類は後から追加してください'), findsOneWidget);
  });

  testWidgets('body failure retains input without claiming saved',
      (tester) async {
    final repository = _Repository()..failBody = true;
    await _open(tester, repository);
    await _save(tester);
    expect(find.text('保存完了'), findsNothing);
    expect(find.textContaining('車両本体は保存済みです。'), findsNothing);
    expect(find.textContaining('保存結果を確認できませんでした'), findsWidgets);
    expect(repository.notified, isEmpty);
    expect(find.text('作業車'), findsOneWidget);
    expect(find.text('品川123'), findsOneWidget);
  });

  testWidgets('subsequent update failure never loses previously returned ID',
      (tester) async {
    final repository = _Repository();
    await _open(tester, repository);
    await _save(tester);
    repository.failBody = true;
    await _save(tester);
    repository.failBody = false;
    repository.failNotice = false;
    await _save(tester);
    expect(repository.ids,
      [null, 'saved-exact-vehicle', 'saved-exact-vehicle']);
    expect(find.text('保存完了'), findsOneWidget);
  });
  testWidgets('upload failure retains exact vehicle and retries only the failed document',
      (tester) async {
    final fixture = await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp('vehicle-upload-test-');
      final registrationBytes = base64Decode('/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAb/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFAEBAAAAAAAAAAAAAAAAAAAABv/EABQRAQAAAAAAAAAAAAAAAAAAAAD/2gAMAwEAAhEDEQA/AJYA4FH/2Q==');
      final compulsoryBytes = base64Decode('/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAP/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFAEBAAAAAAAAAAAAAAAAAAAABv/EABQRAQAAAAAAAAAAAAAAAAAAAAD/2gAMAwEAAhEDEQA/AIABhm//2Q==');
      final registration = await File('${directory.path}/registration.jpg')
          .writeAsBytes(registrationBytes);
      final compulsory = await File('${directory.path}/compulsory.jpg')
          .writeAsBytes(compulsoryBytes);
      return (directory, registration, compulsory, registrationBytes, compulsoryBytes);
    });
    final (directory, registration, compulsory, registrationBytes, compulsoryBytes) = fixture!;
    addTearDown(() => tester.runAsync(() => directory.delete(recursive: true)));
    const channel = MethodChannel('plugins.flutter.io/image_picker');
    final selectedPaths = <String>[registration.path, compulsory.path];
    var picks = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'pickImage');
      expect((call.arguments as Map)['source'], 1); // ImageSource.gallery.
      return selectedPaths[picks++];
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    final repository = _Repository()
      ..failNotice = false
      ..failUploadKind = 'compulsory';
    await _open(tester, repository);
    Future<void> selectPhoto(String title) async {
      final tile = find.ancestor(of: find.text(title), matching: find.byType(ListTile));
      final pick = tester.widget<OutlinedButton>(find.descendant(
          of: tile, matching: find.byType(OutlinedButton))).onPressed!;
      // Preserve the real asynchronous editor callback through native selection
      // and actual XFile.readAsBytes; no production picker seam is introduced.
      await tester.runAsync(() async {
        final pending = (pick as dynamic)() as Future<void>;
        await tester.pumpAndSettle();
        await tester.tap(find.text('写真ライブラリから選ぶ'));
        await tester.pump();
        await pending;
      });
      await tester.pumpAndSettle();
    }
    await selectPhoto('車検証');
    await selectPhoto('自賠責保険');
    expect(picks, 2);
    expect(find.text('今回登録: registration.jpg'), findsOneWidget);
    expect(find.text('今回登録: compulsory.jpg'), findsOneWidget);
    await _save(tester);
    expect(repository.ids, [null]);
    expect(repository.uploads.map((x) => x.kind), ['registration', 'compulsory']);
    expect(repository.uploads.every((x) => x.vehicleId == 'saved-exact-vehicle'), true);
    expect(repository.uploads.every((x) => x.contentType == 'image/jpeg'), true);
    expect(repository.uploads[0].bytes, registrationBytes);
    expect(repository.uploads[1].bytes, compulsoryBytes);
    expect(find.text('今回登録: registration.jpg'), findsNothing);
    expect(find.text('登録済み'), findsOneWidget);
    expect(find.text('今回登録: compulsory.jpg'), findsOneWidget);
    expect(find.textContaining('車両書類の処理を完了できませんでした'), findsWidgets);
    expect(find.text('保存完了'), findsNothing);
    expect(repository.notified, isEmpty);
    repository.failUploadKind = null;
    await _save(tester);
    expect(repository.ids, [null, 'saved-exact-vehicle']);
    expect(repository.uploads.map((x) => x.kind),
        ['registration', 'compulsory', 'compulsory']);
    expect(repository.uploads.last.vehicleId, 'saved-exact-vehicle');
    expect(repository.uploads.last.filename, repository.uploads[1].filename);
    expect(repository.uploads.last.bytes, repository.uploads[1].bytes);
    expect(repository.notified, ['saved-exact-vehicle']);
    expect(find.text('保存完了'), findsOneWidget);
    expect(picks, 2, reason: 'retry must not require selecting photos again');
    expect(tester.takeException(), isNull);
  });

}
