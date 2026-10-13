import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

/// One saved attachment is one slot, even when the file is a multi-page PDF.
class ResourceAttachment {
  const ResourceAttachment({
    required this.label,
    this.path,
    this.loadBytes,
    this.known = true,
    this.validateAccess,
  });
  final String label;
  final String? path;
  final Future<Uint8List> Function()? loadBytes;
  final bool known;
  final Future<void> Function()? validateAccess;
  bool get registered => path?.trim().isNotEmpty == true;
}

ResourceAttachment signedResourceAttachment({
  required String label,
  required String? path,
  required Future<String> Function(String) signedUrl,
  bool known = true,
}) => ResourceAttachment(
  label: label,
  path: path,
  known: known,
  validateAccess: path?.trim().isNotEmpty != true ? null : () async { await signedUrl(path!); },
  loadBytes: path?.trim().isNotEmpty != true ? null : () async {
    final url = await signedUrl(path!);
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 15));
      request.followRedirects = false;
      final response = await request.close().timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) throw StateError('Attachment unavailable');
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(const Duration(seconds: 15))) {
        bytes.add(chunk);
      }
      await signedUrl(path!);
      return bytes.takeBytes();
    } finally {
      client.close(force: true);
    }
  },
);

class ResourceRegistrationCard extends StatelessWidget {
  const ResourceRegistrationCard({
    super.key,
    required this.title,
    required this.icon,
    required this.registered,
    required this.attachments,
    required this.onAction,
    this.dateLabel = '',
    this.statusLabel,
    this.detailLabel = '',
    this.onOpenDetail,
    this.rasterizeFirstPage,
  });
  static const cardHeight = 204.0;
  final String title, dateLabel, detailLabel;
  final IconData icon;
  final bool registered;
  final String? statusLabel;
  final List<ResourceAttachment> attachments;
  final VoidCallback? onAction, onOpenDetail;
  final Future<Uint8List> Function(Uint8List)? rasterizeFirstPage;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final label = statusLabel ?? (registered ? '登録済み' : '未登録');
    final statusColor = registered ? Colors.green.shade700 : Colors.red.shade700;
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final headerHeight = (15 * scale * 1.3 + 12).clamp(44.0, double.infinity).toDouble();
    final statusHeight = (11 * scale * 1.3 + 4).clamp(24.0, double.infinity).toDouble();
    final detailHeight = (11 * scale * 1.3).clamp(20.0, double.infinity).toDouble();
    final thumbnailHeight = (10 * scale * 1.3 + 47).clamp(80.0, double.infinity).toDouble();
    return SizedBox(
      height: 24 + headerHeight + statusHeight + detailHeight + 8 + thumbnailHeight + 4,
      child: Card(
        color: Colors.white,
        margin: EdgeInsets.zero,
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.primary.withValues(alpha: .12)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(height: headerHeight, child: Row(children: [
              CircleAvatar(radius: 17, backgroundColor: colors.primary.withValues(alpha: .09),
                child: Icon(icon, color: colors.primary, size: 22)),
              const SizedBox(width: 8),
              Expanded(child: Tooltip(message: title, child: Text(title, maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.black87)))),
              IconButton(tooltip: '詳細を確認', onPressed: onOpenDetail ?? onAction,
                icon: const Icon(Icons.chevron_right), color: colors.primary),
            ])),
            SizedBox(height: statusHeight, child: Row(children: [
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: statusColor.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(6)),
                child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: statusColor))),
              const SizedBox(width: 8),
              Expanded(child: Text(dateLabel, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Colors.black54))),
            ])),
            SizedBox(height: detailHeight, child: Text(detailLabel, maxLines: 1,
              overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.black54))),
            const SizedBox(height: 8),
            Expanded(child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(child: attachments.isEmpty
                ? const Align(alignment: Alignment.centerLeft,
                    child: Text('登録なし', style: TextStyle(fontSize: 12, color: Colors.black54)))
                : Row(children: [
                    for (final attachment in attachments.take(2)) ...[
                      ResourceAttachmentThumbnail(key: ValueKey('${attachment.label}:${attachment.path ?? ''}'),
                        attachment: attachment, rasterizeFirstPage: rasterizeFirstPage),
                      const SizedBox(width: 6),
                    ],
                  ])),
              const SizedBox(width: 6),
              SizedBox(width: 112, height: (13 * scale * 1.3 + 16).clamp(44.0, double.infinity).toDouble(), child: registered
                ? OutlinedButton(onPressed: onAction,
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8),
                      foregroundColor: colors.primary, side: BorderSide(color: colors.primary),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                    child: const Text('確認・編集', maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)))
                : FilledButton(onPressed: onAction,
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                    child: const Text('登録', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)))),
            ])),
          ]),
        ),
      ),
    );
  }
}

bool _isPdf(Uint8List bytes) => bytes.length >= 5 &&
  bytes[0] == 37 && bytes[1] == 80 && bytes[2] == 68 && bytes[3] == 70 && bytes[4] == 45;

class ResourceAttachmentThumbnail extends StatefulWidget {
  const ResourceAttachmentThumbnail({super.key, required this.attachment, this.rasterizeFirstPage});
  final ResourceAttachment attachment;
  final Future<Uint8List> Function(Uint8List)? rasterizeFirstPage;
  @override
  State<ResourceAttachmentThumbnail> createState() => _ResourceAttachmentThumbnailState();
}

class _ResourceAttachmentThumbnailState extends State<ResourceAttachmentThumbnail> {
  Future<(Uint8List, Uint8List?, bool)>? _content;
  Future<Uint8List>? _original;
  @override
  void initState() { super.initState(); _content = _load(); }
  @override
  void didUpdateWidget(covariant ResourceAttachmentThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachment.path != widget.attachment.path ||
        oldWidget.attachment.known != widget.attachment.known) _content = _load();
  }
  Future<(Uint8List, Uint8List?, bool)>? _load() {
    if (!widget.attachment.registered || widget.attachment.loadBytes == null) {
      _original = null;
      return null;
    }
    _original = widget.attachment.loadBytes!();
    final original = _original!;
    return (() async {
      final bytes = await original;
      if (!_isPdf(bytes)) return (bytes, bytes, false);
      Uint8List? thumbnail;
      try {
        thumbnail = await (widget.rasterizeFirstPage != null
          ? widget.rasterizeFirstPage!(bytes)
          : Printing.raster(bytes, pages: [0], dpi: 36).timeout(const Duration(seconds: 15)).first.then((page) => page.toPng()))
          .timeout(const Duration(seconds: 15));
      } catch (_) { /* The original PDF stays available for full-page preview. */ }
      return (bytes, thumbnail, true);
    })();
  }

  Future<void> _open() async {
    if (_content == null) return;
    final content = _original;
    final path = widget.attachment.path;
    try {
      final bytes = await content!;
      await widget.attachment.validateAccess?.call();
      if (!mounted || content != _original || path != widget.attachment.path) return;
      final pdf = _isPdf(bytes);
      await showDialog<void>(context: context, builder: (context) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(title: Text(widget.attachment.label), leading: IconButton(
            tooltip: '閉じる', icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context))),
          body: pdf ? PdfPreview(build: (_) async => bytes, useActions: false,
            canDebug: false, canChangeOrientation: false, canChangePageFormat: false,
            allowPrinting: false, allowSharing: false, dynamicLayout: false,
            onError: (_, __) => const Center(child: Text('PDFを表示できませんでした。')))
            : Center(child: InteractiveViewer(minScale: .5, maxScale: 5,
                child: Image.memory(bytes, fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Text('画像を表示できませんでした。')))),
        ),
      ));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('添付を表示できませんでした。'),
        action: SnackBarAction(label: '再試行', onPressed: () => setState(() => _content = _load()))));
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox(width: 52, height: (10 * MediaQuery.textScalerOf(context).scale(1) * 1.3 + 47).clamp(80.0, double.infinity).toDouble(),
    child: Column(children: [
      Expanded(child: InkWell(
        onTap: _content == null ? null : _open,
        borderRadius: BorderRadius.circular(6),
        child: Container(width: 52, decoration: BoxDecoration(color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.grey.shade300)),
          child: _content == null ? Center(child: Text(widget.attachment.known ? '未登録' : '未取得',
            style: const TextStyle(fontSize: 10), textAlign: TextAlign.center))
            : FutureBuilder<(Uint8List, Uint8List?, bool)>(future: _content, builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) return const Center(
                  child: SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)));
                if (snapshot.hasError || snapshot.data == null) return const Center(child: Text('読込不可',
                  style: TextStyle(fontSize: 10), textAlign: TextAlign.center));
                if (snapshot.data!.$2 == null) return const Icon(Icons.picture_as_pdf_outlined, size: 24);
                return ClipRRect(borderRadius: BorderRadius.circular(5), child: Image.memory(
                  snapshot.data!.$2!, cacheWidth: 120, cacheHeight: 160, fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Center(child: Text('読込不可', style: TextStyle(fontSize: 10)))));
              }),
        ),
      )),
      const SizedBox(height: 3),
      Text(widget.attachment.label, maxLines: 1, overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 10, color: Colors.black54)),
    ]),
  );
}

Future<void> showResourceAttachments(BuildContext context, {
  required String title, required List<ResourceAttachment> attachments,
}) => showDialog<void>(context: context, builder: (context) => Dialog(
  child: Padding(padding: const EdgeInsets.all(16), child: Column(
    mainAxisSize: MainAxisSize.min, children: [
      Text(title, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 12),
      Flexible(child: SingleChildScrollView(child: Wrap(spacing: 12, runSpacing: 12,
        children: [for (final attachment in attachments)
          ResourceAttachmentThumbnail(attachment: attachment)]))),
      const SizedBox(height: 12),
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('閉じる')),
    ],
  )),
));
