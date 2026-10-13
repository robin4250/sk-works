import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('camera cancellation returns before attendance verification write', () {
    final source =
        File('lib/features/attendance/attendance_verification_page.dart')
            .readAsStringSync();

    final cameraIndex = source.indexOf('ImageSource.camera');
    final cancelIndex = source.indexOf('if (photo == null)', cameraIndex);
    final returnIndex = source.indexOf('return;', cancelIndex);
    final writeIndex = source.indexOf('repository.createVerification', cameraIndex);

    expect(cameraIndex, greaterThanOrEqualTo(0));
    expect(cancelIndex, greaterThan(cameraIndex));
    expect(returnIndex, greaterThan(cancelIndex));
    expect(writeIndex, greaterThan(returnIndex));
    expect(
      source.substring(cancelIndex, writeIndex),
      contains('写真撮影をキャンセルしたため、確認は登録していません。'),
    );
  });
}
