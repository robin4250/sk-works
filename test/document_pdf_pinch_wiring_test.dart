import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String read(String path) => File(path).readAsStringSync();

  test('received data PDF uses pinch pages without removing print or share', () {
    final source = read('lib/features/people/company_delivery_inbox_page.dart');
    final preview = source.substring(source.indexOf('class _ReceivedDataPdfPreviewState'));
    expect(preview, contains('PdfPreview.builder('));
    expect(preview, contains('PdfPinchPages(pages: pages)'));
    expect(preview, contains('build: _buildPreviewPdf'));
    expect(preview, contains('_pdfBytes.get(_buildPdf)'));
    expect(preview, contains('_pdfBytes.invalidate()'));
    expect(preview, contains('allowPrinting: true'));
    expect(preview, contains('allowSharing: true'));
  });

  test('manual variants retain cached output and use stable pinch builder', () {
    final source = read('lib/features/help/manual_pdf_service.dart');
    final preview = source.substring(source.indexOf('class _ManualPdfPreviewPageState'));
    expect(preview, contains('PdfPreview.builder('));
    expect(preview, contains('PdfPinchPages(pages: pages)'));
    expect(preview, contains('build: _buildPreviewPdf'));
    expect(preview, contains('buildChapter(widget._section!, format: format)'));
    expect(preview, contains('buildPamphlet(format: format)'));
    expect(preview, contains('buildRoleManual(widget._role!, format: format)'));
    expect(preview, contains('allowPrinting: true'));
    expect(preview, contains('allowSharing: true'));
  });

  test('seal sample and author PDF retain bytes and actions', () {
    final source = read('lib/features/settings/company_seal_settings_page.dart');
    expect('PdfPreview.builder('.allMatches(source).length, 2);
    expect('PdfPinchPages(pages: pages)'.allMatches(source).length, 2);
    expect('build: buildPreviewPdf'.allMatches(source).length, 2);
    expect('Future<Uint8List> buildPreviewPdf(PdfPageFormat _) async => bytes;'
        .allMatches(source).length, 2);
    expect('allowPrinting: true'.allMatches(source).length, 2);
    expect('allowSharing: true'.allMatches(source).length, 2);
  });
  test('registered PDF attachment permits print but keeps sharing disabled', () {
    final source = read('lib/features/shared/resource_registration_card.dart');
    expect(source, contains('PdfPreview.builder(build: buildPreviewPdf'));
    expect(source, contains('PdfPinchPages(pages: pages)'));
    expect(source, contains('allowPrinting: true, allowSharing: false'));
    expect(source, contains('await widget.attachment.validateAccess?.call()'));
    expect(source, contains('Future<Uint8List> buildPreviewPdf(PdfPageFormat _) async {'));
    expect(source, contains("if (!mounted || !widget.isCurrent()) { throw StateError('Attachment scope changed'); }"));
    expect(source, contains('return bytes;'));
    // The runtime gallery test retains this callback across invalidation and
    // verifies it rejects, rather than returning saved PDF bytes after logout.
  });

}
