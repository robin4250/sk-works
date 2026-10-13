import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/invoices/invoice_preview_raster.dart';

void main() {
  test('all genuine raster pages retain their bytes and order', () async {
    final first = Uint8List.fromList([1, 2]), second = Uint8List.fromList([3, 4]);
    final pages = await collectInvoicePreviewPages(Stream.fromIterable([first, second]));
    expect(pages, [same(first), same(second)]);
  });
  test('empty native stream and empty image fail instead of blank preview', () async {
    await expectLater(collectInvoicePreviewPages(const Stream<Uint8List>.empty()), throwsStateError);
    await expectLater(collectInvoicePreviewPages(Stream.value(Uint8List(0))), throwsStateError);
  });
  test('stalled native stream times out, cancels and permits a fresh retry', () async {
    var cancelled = false;
    final controller = StreamController<Uint8List>(onCancel: () { cancelled = true; });
    await expectLater(collectInvoicePreviewPages(controller.stream, idleTimeout: const Duration(milliseconds: 10)), throwsStateError);
    expect(cancelled, isTrue);
    await controller.close();
    expect(await collectInvoicePreviewPages(Stream.value(Uint8List.fromList([5]))), hasLength(1));
  });
  test('native rendering failures propagate without replacing saved PDF', () async {
    final failure = StateError('native rendering unavailable');
    await expectLater(collectInvoicePreviewPages(Stream<Uint8List>.error(failure)), throwsA(same(failure)));
  });
  test('invalid dimensions, malformed RGBA and transparent native pages never encode', () async {
    var encoded = 0;
    Future<Uint8List> encode() async { encoded++; return Uint8List.fromList([1]); }
    for (final input in [
      (width: 0, height: 1, pixels: Uint8List(0)),
      (width: -1, height: 1, pixels: Uint8List(4)),
      (width: 1, height: 0, pixels: Uint8List(0)),
      (width: 1, height: 1, pixels: Uint8List(3)),
      (width: 1, height: 1, pixels: Uint8List(5)),
      (width: 2, height: 1, pixels: Uint8List(8)),
      (width: 1, height: 1, pixels: Uint8List.fromList([255, 255, 255, 0])),
    ]) {
      await expectLater(encodeInvoicePreviewRaster(
        width: input.width, height: input.height, pixels: input.pixels, encode: encode,
      ), throwsStateError);
    }
    expect(encoded, 0);
  });
  test('opaque white and sparse visible RGBA pages retain the exact encoder output', () async {
    final png = Uint8List.fromList([137, 80, 78, 71]);
    for (final pixels in [
      Uint8List.fromList([255, 255, 255, 255]),
      Uint8List.fromList([0, 0, 0, 0, 12, 24, 36, 1]),
    ]) {
      var encoded = 0;
      final result = await encodeInvoicePreviewRaster(
        width: pixels.length ~/ 4, height: 1, pixels: pixels,
        encode: () async { encoded++; return png; },
      );
      expect(encoded, 1);
      expect(result, same(png));
    }
  });
}
