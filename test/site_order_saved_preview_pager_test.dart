import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:printing/printing.dart';
// The exact pinned platform primitive lets this test exercise real gestures
// over an actual decoded bitmap, without a native PDFium installation.
// ignore: implementation_imports
import 'package:printing/src/interface.dart' show PrintingPlatform;
import 'package:sk_works/features/sites/site_order_saved_preview_pager.dart';

class _Raster extends PrintingPlatform {
  @override
  Stream<PdfRaster> raster(
    Uint8List document,
    List<int>? pages,
    double dpi,
  ) async* {
    yield PdfRaster(8, 8, Uint8List.fromList(List.filled(8 * 8 * 4, 255)));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final bytes = Uint8List.fromList(ascii.encode('%PDF-immutable saved fixture'));
SiteOrderSavedEntry entry(int n) => SiteOrderSavedEntry(
  packageId: '00000000-0000-0000-0000-${n.toString().padLeft(12, '0')}',
  title: '現場$n',
  startsOn: '',
  endsOn: '',
  pdfSha256: sha256.convert(bytes).toString(),
);
void main() {
  test('read-only entry accepts missing prices/dates without inventing financial values', () {
    expect(entry(1).period, '工期未設定');
    expect(
      () => SiteOrderSavedEntry(
        packageId: entry(1).packageId,
        title: '現場',
        startsOn: '',
        endsOn: '',
        pdfSha256: 'wrong',
      ),
      throwsFormatException,
    );
  });
  testWidgets(
    'valid bitmap preview swipes work titles and clears images when scope retires',
    (tester) async {
      final old = PrintingPlatform.instance;
      PrintingPlatform.instance = _Raster();
      final changes = ChangeNotifier();
      var alive = true;
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: SiteOrderSavedPreviewPager(
              entries: [entry(1), entry(2)],
              initialIndex: 0,
              requireScope: () {
                if (!alive) throw StateError('retired');
              },
              scopeChanges: changes,
              loadPdf: (_) async => bytes,
            ),
          ),
        );
        for (var n = 0; n < 100 && find.byType(Image).evaluate().isEmpty; n++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(find.byType(Image), findsWidgets);
        await tester.drag(
          find.byType(InteractiveViewer).first,
          const Offset(-600, 0),
        );
        await tester.pump(const Duration(milliseconds: 500));
        // Raster decoding runs outside the fake widget clock. Wait for the
        // second bitmap explicitly instead of settling its loading animation.
        for (
          var n = 0;
          n < 100 &&
              find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
          n++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(
          find.descendant(of: find.byType(AppBar), matching: find.text('現場2')),
          findsOneWidget,
        );
        expect(find.byTooltip('閉じる'), findsOneWidget);
        alive = false;
        changes.notifyListeners();
        await tester.pumpAndSettle();
        expect(find.byType(Image), findsNothing);
        expect(find.text('現場2'), findsNothing);
        expect(find.byTooltip('閉じる'), findsOneWidget);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        PrintingPlatform.instance = old;
        changes.dispose();
      }
    },
  );
  testWidgets(
    'approaching the end appends the next protected history page once',
    (tester) async {
      final changes = ChangeNotifier();
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: SiteOrderSavedPreviewPager(
            entries: [entry(1), entry(2)],
            initialIndex: 0,
            hasMore: true,
            requireScope: () {},
            scopeChanges: changes,
            loadPdf: (_) async => bytes,
            loadMore: () async {
              calls++;
              return [entry(3)];
            },
            entryBuilder: (e) => Center(child: Text('原本${e.packageId}')),
          ),
        ),
      );
      await tester.drag(find.byType(PageView), const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.text('工期未設定   2 / 3件'), findsOneWidget);
      await tester.drag(find.byType(PageView), const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('現場3')),
        findsOneWidget,
      );
      expect(calls, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      changes.dispose();
    },
  );
}
