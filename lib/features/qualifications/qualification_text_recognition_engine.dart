import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class QualificationTextRecognitionEngine {
  const QualificationTextRecognitionEngine();

  Future<String> recognizeImagePath(String imagePath) async {
    if (!Platform.isIOS) {
      throw UnsupportedError(
        '資格証の日本語OCRは現在iPhone実機確認を優先しています。',
      );
    }

    final recognizer = TextRecognizer(
      script: TextRecognitionScript.japanese,
    );
    try {
      final image = InputImage.fromFilePath(imagePath);
      final result = await recognizer.processImage(image);
      return result.text.trim();
    } finally {
      await recognizer.close();
    }
  }
}
