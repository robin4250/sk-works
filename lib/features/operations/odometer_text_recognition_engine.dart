import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OdometerRecognitionResult {
  const OdometerRecognitionResult({
    required this.rawText,
    required this.candidates,
  });

  final String rawText;
  final List<double> candidates;

  double? get bestCandidate => candidates.isEmpty ? null : candidates.first;
}

class OdometerTextRecognitionEngine {
  const OdometerTextRecognitionEngine();

  Future<OdometerRecognitionResult> recognizeImagePath(
    String imagePath,
  ) async {
    if (!Platform.isIOS) {
      throw UnsupportedError(
        '走行距離OCRはiPhone実機で利用します。',
      );
    }

    final recognizer = TextRecognizer(
      script: TextRecognitionScript.latin,
    );
    try {
      final image = InputImage.fromFilePath(imagePath);
      final result = await recognizer.processImage(image);
      final raw = result.text.trim();
      final candidates = _extractCandidates(raw);
      return OdometerRecognitionResult(
        rawText: raw,
        candidates: candidates,
      );
    } finally {
      await recognizer.close();
    }
  }

  List<double> _extractCandidates(String raw) {
    final values = <double>{};
    final matches = RegExp(r'(?<!\d)(\d{2,8}(?:[.,]\d)?)(?!\d)')
        .allMatches(raw.replaceAll(' ', ''));

    for (final match in matches) {
      final text = match.group(1)?.replaceAll(',', '.');
      final value = double.tryParse(text ?? '');
      if (value == null || value < 0 || value > 99999999.9) continue;
      values.add(value);
    }

    final sorted = values.toList()
      ..sort((a, b) {
        final digitsA = a.floor().toString().length;
        final digitsB = b.floor().toString().length;
        if (digitsA != digitsB) return digitsB.compareTo(digitsA);
        return b.compareTo(a);
      });
    return sorted;
  }
}
