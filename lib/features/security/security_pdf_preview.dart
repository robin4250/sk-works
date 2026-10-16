import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';

import '../shared/pdf_pinch_pages.dart';

/// Lives inside the existing fresh Master/actor boundary, never another route.
class SecurityPdfPreview extends StatefulWidget {
  const SecurityPdfPreview({
    super.key,
    required this.authorize,
    required this.buildPdf,
    required this.printPdf,
    required this.sharePdf,
    this.english = false,
    this.previewBuilder,
  });

  final Future<void> Function() authorize;
  final Future<Uint8List> Function() buildPdf;
  final Future<void> Function(Uint8List) printPdf;
  final Future<void> Function(Uint8List) sharePdf;
  final bool english;
  @visibleForTesting
  final Widget Function(Uint8List)? previewBuilder;

  @override
  State<SecurityPdfPreview> createState() => _SecurityPdfPreviewState();
}

class _SecurityPdfPreviewState extends State<SecurityPdfPreview> {
  Uint8List? _bytes;
  bool _failed = false;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await widget.authorize();
      if (!mounted) return;
      final bytes = await widget.buildPdf();
      await widget.authorize();
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _busy = false;
      });
    } catch (_) {
      if (mounted) setState(() {
        _bytes = null;
        _failed = true;
        _busy = false;
      });
    }
  }

  Future<Uint8List> _previewPdf(PdfPageFormat format) async =>
      _bytes ?? (throw StateError('Unavailable'));

  Future<void> _handoff(Future<void> Function(Uint8List) output) async {
    final bytes = _bytes;
    if (_busy || bytes == null || _failed) return;
    setState(() => _busy = true);
    try {
      await widget.authorize();
      if (!mounted) return;
      await output(bytes);
      if (mounted) setState(() => _busy = false);
    } catch (_) {
      if (mounted) setState(() {
        _bytes = null;
        _failed = true;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.english ? 'Security PDF preview' : 'セキュリティPDFプレビュー')),
    body: _failed
        ? Center(child: Text(widget.english ? 'Export unavailable. Close and reopen this screen.' : '出力できません。画面を閉じて開き直してください。'))
        : _bytes == null
            ? const Center(child: CircularProgressIndicator())
            : Column(children: [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(widget.english ? 'Pinch with two fingers to zoom.' : '2本の指で広げると拡大できます。'),
                ),
                Expanded(child: widget.previewBuilder?.call(_bytes!) ??
                  PdfPreview.builder(
                    build: _previewPdf,
                    allowPrinting: false,
                    allowSharing: false,
                    canChangeOrientation: false,
                    canChangePageFormat: false,
                    canDebug: false,
                    pagesBuilder: (context, pages) => PdfPinchPages(pages: pages),
                  )),
                SafeArea(top: false, child: Wrap(spacing: 8, children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _handoff(widget.printPdf),
                    icon: const Icon(Icons.print_outlined),
                    label: Text(widget.english ? 'Print' : '印刷'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _handoff(widget.sharePdf),
                    icon: const Icon(Icons.save_alt),
                    label: Text(widget.english ? 'Save / share' : '保存・共有'),
                  ),
                ])),
              ]),
  );
}
