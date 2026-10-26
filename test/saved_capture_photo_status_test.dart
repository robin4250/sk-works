import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/attendance/saved_capture_photo_status.dart';
import 'package:sk_works/widgets/input_step_heading.dart';

void main() {
  final metadata = <String, dynamic>{
    'photo_capture_status': 'uploaded',
    'photo_storage_path': 'fixture/photo.jpg',
  };
  test('an upload alone never represents a saved attendance record', () {
    expect(savedCapturePhotoRegistered(null), isFalse);
    expect(savedCapturePhotoRegistered(metadata), isFalse);
    expect(savedCapturePhotoRegistered({'id': 'receipt', ...metadata}), isTrue);
    expect(savedCapturePhotoRegistered({'id': 'receipt', 'payload': metadata}), isTrue);
  });
  test('missing, failed, archived or empty-path photos are not registered', () {
    for (final row in <Map<String, dynamic>>[
      {'id': 'receipt'},
      {'id': 'receipt', ...metadata, 'archived': true},
      {'id': 'receipt', ...metadata, 'photo_capture_status': 'upload_failed'},
      {'id': 'receipt', ...metadata, 'photo_storage_path': '  '},
      {'id': '', ...metadata},
    ]) {
      expect(savedCapturePhotoRegistered(row), isFalse);
    }
  });
  testWidgets('saved status remains readable on a narrow enlarged display', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
      child: const Scaffold(body: InputStepHeading(number: '③',
        title: '写真を撮影し、位置情報と一緒に登録', status: '写真登録済み', complete: true)),
    )));
    expect(find.text('写真登録済み'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
