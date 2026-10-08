import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/shared/pdf_bytes_cache.dart';

void main() {
  test('concurrent preview, print and share reuse the same PDF bytes', () async {
    final cache = PdfBytesCache();
    final pending = Completer<Uint8List>();
    var builds = 0;
    Future<Uint8List> build() {
      builds++;
      return pending.future;
    }
    final preview = cache.get(build);
    final printFuture = cache.get(build);
    final share = cache.get(build);
    expect(identical(preview, printFuture), isTrue);
    expect(identical(printFuture, share), isTrue);
    final bytes = Uint8List.fromList([1, 2, 3]);
    pending.complete(bytes);
    expect(identical(await preview, bytes), isTrue);
    expect(identical(await cache.get(build), bytes), isTrue);
    expect(builds, 1);
  });

  test('failed generation can retry and preserves the actual error', () async {
    final cache = PdfBytesCache();
    final failure = StateError('font loading failed');
    await expectLater(cache.get(() => throw failure), throwsA(same(failure)));
    final bytes = Uint8List.fromList([4]);
    expect(await cache.get(() => bytes), same(bytes));
  });

  test('data invalidation builds new PDF bytes', () async {
    final cache = PdfBytesCache();
    final old = Uint8List.fromList([1]);
    final updated = Uint8List.fromList([2]);
    expect(await cache.get(() => old), same(old));
    cache.invalidate();
    expect(await cache.get(() => updated), same(updated));
  });

  test('invalidated old failure cannot evict a newer successful generation', () async {
    final cache = PdfBytesCache();
    final old = Completer<Uint8List>();
    final stale = cache.get(() => old.future);
    final errorCheck = expectLater(stale, throwsStateError);
    cache.invalidate();
    final bytes = Uint8List.fromList([5]);
    final refreshed = cache.get(() => bytes);
    old.completeError(StateError('old generation'));
    await errorCheck;
    expect(await refreshed, same(bytes));
    expect(cache.get(() => throw StateError('must not rebuild')), same(refreshed));
  });
}
