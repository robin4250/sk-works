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
}
