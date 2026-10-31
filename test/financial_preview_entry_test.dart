import 'dart:typed_data';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
// The pinned printing 5.15.1 interface lets the actual entry build without a
// platform printer or network raster service.
// ignore: implementation_imports
import 'package:printing/src/interface.dart' show PrintingPlatform;
import 'package:sk_works/domain/invoice_engine.dart';
import 'package:sk_works/features/invoices/invoice_cloud_page.dart';
import 'package:sk_works/features/payroll/payment_certificate_repository.dart';
import 'package:sk_works/features/payroll/payment_certificates_page.dart';
import 'package:sk_works/features/shared/financial_preview_chrome.dart';

// Fonts are served from the repository asset through an in-memory HttpClient.
// This keeps Google-font HTTP fallback timeouts out of the widget FakeAsync
// clock and makes repeated real-page mounts deterministic without a network.
class _FontHttp extends HttpOverrides {
  final Uint8List bytes = File('assets/fonts/company-seal/NotoSansJP-Bold.ttf')
      .readAsBytesSync();
  @override
  HttpClient createHttpClient(SecurityContext? context) => _FontClient(bytes);
}

class _FontClient implements HttpClient {
  _FontClient(this.bytes);
  final Uint8List bytes;
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    if (method != 'GET' ||
        url.scheme != 'https' ||
        url.host != 'fonts.gstatic.com') {
      throw StateError('Unexpected fixture request');
    }
    return _FontRequest(bytes);
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('GET', url);
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Headers implements HttpHeaders {
  @override
  void forEach(void Function(String, List<String>) action) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FontRequest implements HttpClientRequest {
  _FontRequest(this.bytes);
  final Uint8List bytes;
  @override
  final HttpHeaders headers = _Headers();
  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await stream.drain<void>();
  }

  @override
  Future<HttpClientResponse> close() async => _FontResponse(bytes);
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FontResponse extends Stream<List<int>> implements HttpClientResponse {
  _FontResponse(this.bytes);
  final Uint8List bytes;
  @override
  int get statusCode => 200;
  @override
  bool get isRedirect => false;
  @override
  bool get persistentConnection => false;
  @override
  String get reasonPhrase => 'OK';
  @override
  int get contentLength => bytes.length;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  final HttpHeaders headers = _Headers();
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(bytes).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Raster extends PdfRaster {
  _Raster() : super(1, 1, Uint8List.fromList([255, 255, 255, 255]));
  // Synthetic platform raster bytes, not a visual PDF-content proof. Avoid a
  // native image encoder Future captured in FakeAsync when mounting real entry.
  @override
  Future<Uint8List> toPng() async => base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4////fwAJ+wP9KobjigAAAABJRU5ErkJggg==',
  );
}

class _Printer extends PrintingPlatform {
  LayoutCallback? layout;
  Completer<bool>? completed;
  @override
  Future<bool> layoutPdf(
    Printer? printer,
    LayoutCallback onLayout,
    String name,
    PdfPageFormat format,
    bool dynamicLayout,
    bool usePrinterSettings,
    OutputType outputType,
    bool forceCustomPrintPaper,
    bool windowsModernDialog,
  ) {
    layout = onLayout;
    completed = Completer<bool>();
    return completed!.future;
  }

  @override
  Future<PrintingInfo> info() async =>
      const PrintingInfo(canPrint: true, canShare: true, canRaster: true);
  @override
  Stream<PdfRaster> raster(
    Uint8List document,
    List<int>? pages,
    double dpi,
  ) async* {
    expect(String.fromCharCodes(document.take(4)), '%PDF');
    yield _Raster();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PrintingPlatform original;
  late _Printer printer;
  setUp(() {
    original = PrintingPlatform.instance;
    printer = _Printer();
    PrintingPlatform.instance = printer;
  });
  tearDown(() {
    if (printer.completed != null && !printer.completed!.isCompleted) {
      printer.completed!.complete(false);
    }
    PrintingPlatform.instance = original;
  });
  for (final payment in [false, true]) {
    for (final narrow in [false, true]) {
      testWidgets(
        'actual ${payment ? 'payment' : 'invoice'} entry keeps one compact footer narrow=$narrow',
        (tester) async => HttpOverrides.runWithHttpOverrides(() async {
          tester.view.physicalSize = Size(narrow ? 320 : 430, 932);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final invoice = InvoiceEngine.calculate(
            customerId: 'Synthetic company',
            billingPeriod: '2026年9月',
            detailMode: InvoiceDetailMode.siteBreakdownOnInvoice,
            sites: const [
              SiteInvoiceCalculation(
                siteId: 'synthetic-site',
                siteName: 'Synthetic site',
                lines: [
                  InvoiceLine(label: 'work', quantity: 1, unitPriceYen: 100),
                ],
              ),
            ],
          );
          final record = PaymentCertificateRecord(
            id: 'synthetic-preview',
            partnerCompanyName: 'Synthetic partner',
            periodStart: DateTime(2026, 9),
            periodEnd: DateTime(2026, 9, 30),
            grossAmount: 100,
            deductions: 0,
            netAmount: 100,
            status: 'preview',
            revision: 1,
          );
          await tester.pumpWidget(
            MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(narrow ? 2 : 1)),
                child: child!,
              ),
              home: payment
                  ? PaymentCertificatePreviewPage(record: record)
                  : InvoicePreviewPage(invoice: invoice),
            ),
          );
          // PDF font fallback and PNG conversion use real async work; advance them
          // outside FakeAsync, then render frames. No timeout enlargement or real RPC.
          for (
            var stage = 0;
            stage < 100 &&
                (find.byType(FinancialPreviewChrome).evaluate().isEmpty ||
                    (!payment &&
                        find.byType(InteractiveViewer).evaluate().isEmpty));
            stage++
          ) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)),
            );
            await tester.pump();
          }
          expect(find.byType(FinancialPreviewChrome), findsOneWidget);
          if (!payment) {
            expect(find.byType(InteractiveViewer), findsOneWidget);
          }
          expect(find.byType(Scaffold), findsOneWidget);
          final viewport = tester.getSize(
            find.byKey(const ValueKey('financial_preview_document_viewport')),
          );
          expect(viewport.height, greaterThan(narrow ? 300 : 550));
          expect(
            find.byKey(const ValueKey('financial_preview_footer')),
            findsOneWidget,
          );
          if (payment) {
            final preview = tester.widget<PdfPreview>(find.byType(PdfPreview));
            expect(preview.useActions, isFalse);
            expect(preview.initialPageFormat, PdfPageFormat.a4);
          }
          if (payment) {
            await tester.tap(find.widgetWithText(OutlinedButton, '印刷'));
            for (
              var stage = 0;
              stage < 100 && printer.layout == null;
              stage++
            ) {
              await tester.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 20)),
              );
              await tester.pump();
            }
            expect(printer.layout, isNotNull);
            final bytes = await printer.layout!(PdfPageFormat.a4);
            expect(String.fromCharCodes(bytes.take(4)), '%PDF');
            // A replaced document must invalidate the already handed native
            // callback, even when the current actor remains the same.
            final originalState = tester.state(
              find.byType(PaymentCertificatePreviewPage),
            );
            await tester.pumpWidget(
              MaterialApp(
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(narrow ? 2 : 1)),
                  child: child!,
                ),
                home: PaymentCertificatePreviewPage(
                  record: PaymentCertificateRecord(
                    id: 'replacement',
                    partnerCompanyName: 'Synthetic partner',
                    periodStart: record.periodStart,
                    periodEnd: record.periodEnd,
                    grossAmount: 100,
                    deductions: 0,
                    netAmount: 100,
                    status: 'preview',
                    revision: 2,
                  ),
                ),
              ),
            );
            expect(
              identical(
                tester.state(find.byType(PaymentCertificatePreviewPage)),
                originalState,
              ),
              isTrue,
            );
            await expectLater(
              printer.layout!(PdfPageFormat.a4),
              throwsStateError,
            );
            printer.completed!.complete(false);
            await tester.pump();
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
        }, _FontHttp()),
      );
    }
  }
}
