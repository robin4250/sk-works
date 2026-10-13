import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../international/language_controller.dart';
import 'invoice_preview_failure.dart';

/// The iPhone displays the original PDF with PDFKit, without an intermediate
/// Printing RGBA/PNG image. Printing and sharing still use these exact bytes.
class InvoiceNativePdfController {
  InvoiceNativePdfController(this.channel);
  final MethodChannel channel;

  Future<void> load(Uint8List bytes) async {
    final count = await channel.invokeMethod<int>('load', bytes)
        .timeout(const Duration(seconds: 30));
    if (count == null || count <= 0) {
      throw StateError(SkoLanguageController.tr('PDFのページを表示できませんでした。再試行してください。'));
    }
  }

  Future<void> zoom(double scale) => channel.invokeMethod<void>(
    'zoom', scale.clamp(1.0, 5.0),
  );
}

class InvoiceNativePdfView extends StatefulWidget {
  const InvoiceNativePdfView({super.key, required this.pdfBytes});
  final Uint8List pdfBytes;

  @override
  State<InvoiceNativePdfView> createState() => _InvoiceNativePdfViewState();
}

class _InvoiceNativePdfViewState extends State<InvoiceNativePdfView> {
  InvoiceNativePdfController? _controller;
  bool _ready = false;
  String? _error;
  double _scale = 1;
  int _generation = 0;

  Future<void> _load() async {
    final controller = _controller;
    if (controller == null) return;
    final generation = ++_generation;
    setState(() { _ready = false; _error = null; });
    try {
      await controller.load(widget.pdfBytes);
      if (!mounted || generation != _generation) return;
      setState(() { _ready = true; _scale = 1; });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = SkoLanguageController.tr('PDFのページを表示できませんでした。再試行してください。'));
    }
  }

  void _created(int id) {
    final channel = MethodChannel('sko.invoice_pdf_view/$id');
    _controller = InvoiceNativePdfController(channel);
    channel.setMethodCallHandler((call) async {
      if (call.method == 'scale' && call.arguments is num && mounted) {
        final value = (call.arguments as num).toDouble();
        if (value.isFinite) setState(() => _scale = value.clamp(1.0, 5.0).toDouble());
      }
    });
    _load();
  }

  @override
  void didUpdateWidget(covariant InvoiceNativePdfView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.pdfBytes, widget.pdfBytes)) _load();
  }

  @override
  void dispose() {
    _generation++;
    _controller?.channel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      IconButton(tooltip: SkoLanguageController.tr('縮小'),
        onPressed: _ready && _scale > 1.01 ? () => _controller?.zoom(_scale / 1.4) : null,
        icon: const Icon(Icons.zoom_out)),
      TextButton(onPressed: _ready ? () => _controller?.zoom(1) : null,
        child: Text('${(_scale * 100).round()}%')),
      IconButton(tooltip: SkoLanguageController.tr('拡大'),
        onPressed: _ready && _scale < 4.99 ? () => _controller?.zoom(_scale * 1.4) : null,
        icon: const Icon(Icons.zoom_in)),
    ]),
    Expanded(child: Stack(children: [
      Positioned.fill(child: UiKitView(viewType: 'sko.invoice_pdf_view',
        onPlatformViewCreated: _created)),
      if (_error != null)
        Positioned.fill(child: ColoredBox(color: Theme.of(context).colorScheme.surface,
          child: InvoicePreviewFailure(title: 'PDFを表示できませんでした',
            message: _error!, onRetry: _load, pdfReady: true)))
      else if (!_ready)
        const Positioned.fill(child: Center(child: CircularProgressIndicator())),
    ])),
  ]);
}
