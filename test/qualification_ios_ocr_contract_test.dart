import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS preparation pins Japanese OCR native requirements', () {
    final script = File('tool/prepare_ios.sh').readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final engine = File(
      'lib/features/qualifications/qualification_text_recognition_engine.dart',
    ).readAsStringSync();

    expect(pubspec, contains('google_mlkit_text_recognition: 0.17.1'));
    expect(script, contains("platform :ios, '"));
    expect(script, contains('15.5'));
    expect(script, contains('GoogleMLKit/TextRecognitionJapanese'));
    expect(script, contains('EXCLUDED_ARCHS[sdk=*]'));
    expect(engine, contains('TextRecognitionScript.japanese'));
    expect(engine, contains('InputImage.fromFilePath'));
    expect(engine, contains('recognizer.close()'));
  });
}
