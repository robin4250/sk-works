import 'package:flutter/material.dart';
import '../../international/language_controller.dart';

/// Scrolling failure content fits short iPhone viewports and enlarged text.
class InvoicePreviewFailure extends StatelessWidget {
  const InvoicePreviewFailure({
    super.key,
    required this.title,
    required this.message,
    required this.onRetry,
    this.pdfReady = false,
  });
  final String title, message;
  final VoidCallback onRetry;
  final bool pdfReady;

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.picture_as_pdf_outlined, size: 44),
            const SizedBox(height: 12),
            Text(SkoLanguageController.tr(title),
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(SkoLanguageController.tr('再試行')),
            ),
            if (pdfReady) ...[
              const SizedBox(height: 8),
              Text(SkoLanguageController.tr('下の印刷・保存共有ボタンから同じPDFを開くこともできます。'),
                textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }
}
