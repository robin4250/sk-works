import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/invoices/invoice_native_pdf_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('sko.invoice_pdf_view/test');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('PDFKit receives original PDF bytes, including every page, without a PNG conversion', () async {
    final bytes = Uint8List.fromList('%PDF-1.7\noriginal document'.codeUnits);
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'load');
      expect(call.arguments, bytes);
      return 3;
    });
    await InvoiceNativePdfController(channel).load(bytes);
  });

  test('zero or missing native pages surface a retryable failure', () async {
    for (final count in [0, -1, null]) {
      messenger.setMockMethodCallHandler(channel, (_) async => count);
      await expectLater(InvoiceNativePdfController(channel).load(Uint8List(1)), throwsStateError);
    }
  });

  test('native PDF parsing errors propagate and a later load can succeed', () async {
    var first = true;
    messenger.setMockMethodCallHandler(channel, (_) async {
      if (first) { first = false; throw PlatformException(code: 'invalid_pdf'); }
      return 1;
    });
    final controller = InvoiceNativePdfController(channel);
    await expectLater(controller.load(Uint8List(1)), throwsA(isA<PlatformException>()));
    await controller.load(Uint8List(2));
  });

  test('toolbar zoom keeps the same bounded range as the existing preview', () async {
    final calls = <double>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'zoom');
      calls.add((call.arguments as num).toDouble());
      return null;
    });
    final controller = InvoiceNativePdfController(channel);
    await controller.zoom(.5);
    await controller.zoom(2);
    await controller.zoom(20);
    expect(calls, [1, 2, 5]);
  });
}
