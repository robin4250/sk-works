import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

/// Pinch works immediately, without Printing's double-tap zoom mode.
class PdfPinchPages extends StatefulWidget {
  const PdfPinchPages({super.key, required this.pages, this.onZoomChanged});
  final List<PdfPreviewPageData> pages;
  final ValueChanged<bool>? onZoomChanged;

  @override
  State<PdfPinchPages> createState() => _PdfPinchPagesState();
}

class _PdfPinchPagesState extends State<PdfPinchPages> {
  final _transform = TransformationController();
  bool _zoomed = false;

  void _changed() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
    if (_zoomed == zoomed) return;
    _zoomed = zoomed;
    widget.onZoomChanged?.call(zoomed);
  }

  @override
  void initState() {
    super.initState();
    _transform.addListener(_changed);
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => InteractiveViewer(
    key: const ValueKey('pdf-pinch-viewer'),
    transformationController: _transform,
    minScale: 1,
    maxScale: 5,
    child: ListView(
      padding: const EdgeInsets.all(8),
      children: [for (final page in widget.pages)
        Padding(padding: const EdgeInsets.only(bottom: 8),
          child: AspectRatio(aspectRatio: page.aspectRatio,
            child: Image(image: page.image, fit: BoxFit.contain))),
      ],
    ),
  );
}
