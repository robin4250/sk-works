import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'pdf_pinch_pages.dart';
import '../../international/language_controller.dart';

/// One saved attachment is one slot, even when the file is a multi-page PDF.
class ResourceAttachment {
  const ResourceAttachment({
    required this.label,
    this.path,
    this.loadBytes,
    this.known = true,
    this.validateAccess, this.previewKey, this.recordTitle,
  });
  final String label;
  final String? previewKey, recordTitle;
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
  bool known = true, String? previewKey, String? recordTitle,
}) => ResourceAttachment(
  label: label, previewKey: previewKey, recordTitle: recordTitle,
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
      await signedUrl(path);
      return bytes.takeBytes();
    } finally {
      client.close(force: true);
    }
  },
);

/// A fixed, already-authorized worker/company response, never a gallery query.
class ResourceAttachmentGallery {
  ResourceAttachmentGallery({required this.source, required this.workerId,
    required this.companyId, required this.isCurrent, this.changes, this.signal, required Iterable<ResourceAttachment> entries})
      : entries = List.unmodifiable(entries.where((entry) => entry.registered && entry.loadBytes != null)) {
    final keys = this.entries.map((entry) => entry.previewKey).toList();
    if (workerId.isEmpty || companyId.isEmpty || keys.any((key) => key == null || key.isEmpty) ||
        keys.toSet().length != keys.length || this.entries.any((entry) => entry.recordTitle?.trim().isNotEmpty != true)) {
      throw ArgumentError('Invalid saved attachment gallery scope');
    }
  }
  final Stream<Object?>? changes;
  final Listenable? signal;
  final Object source;
  final String workerId, companyId;
  final bool Function() isCurrent;
  final List<ResourceAttachment> entries;
  int indexOf(ResourceAttachment entry) => entries.indexWhere((saved) =>
    saved.previewKey == entry.previewKey && saved.path == entry.path);
}

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
    this.registeredActionLabel = '確認・編集',
    this.detailLabel = '',
    this.onOpenDetail,
    this.rasterizeFirstPage, this.gallery, this.requireGalleryScope = false,
  });
  static const cardHeight = 204.0;
  final ResourceAttachmentGallery? gallery;
  final bool requireGalleryScope;
  final String title, dateLabel, detailLabel;
  final IconData icon;
  final bool registered;
  final String? statusLabel;
  final String registeredActionLabel;
  final List<ResourceAttachment> attachments;
  final VoidCallback? onAction, onOpenDetail;
  final Future<Uint8List> Function(Uint8List)? rasterizeFirstPage;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final label = SkoLanguageController.tr(statusLabel ?? (registered ? '登録済み' : '未登録'));
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
              IconButton(tooltip: SkoLanguageController.tr('詳細を確認'), onPressed: onOpenDetail ?? onAction,
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
            SizedBox(height: detailHeight, child: Tooltip(message: detailLabel,
              child: Text(detailLabel, maxLines: 1,
                overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.black54)))),
            const SizedBox(height: 8),
            Expanded(child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(child: attachments.isEmpty
                ? Align(alignment: Alignment.centerLeft,
                    child: Text(SkoLanguageController.tr('登録なし'), style: const TextStyle(fontSize: 12, color: Colors.black54)))
                : Row(children: [
                    for (final attachment in attachments.take(2)) ...[
                      ResourceAttachmentThumbnail(key: ValueKey('${attachment.label}:${attachment.path ?? ''}'),
                        attachment: attachment, rasterizeFirstPage: rasterizeFirstPage, gallery: gallery, recordTitle: title, requireGalleryScope: requireGalleryScope),
                      const SizedBox(width: 6),
                    ],
                  ])),
              const SizedBox(width: 6),
              SizedBox(width: 112, height: (13 * scale * 1.3 + 16).clamp(44.0, double.infinity).toDouble(), child: registered
                ? OutlinedButton(onPressed: onAction,
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8),
                      foregroundColor: colors.primary, side: BorderSide(color: colors.primary),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                    child: Text(SkoLanguageController.tr(registeredActionLabel), maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)))
                : FilledButton(onPressed: onAction,
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                    child: Text(SkoLanguageController.tr('登録'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)))),
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
  const ResourceAttachmentThumbnail({super.key, required this.attachment, this.rasterizeFirstPage, this.gallery, this.recordTitle, this.requireGalleryScope = false});
  final ResourceAttachment attachment;
  final ResourceAttachmentGallery? gallery;
  final String? recordTitle;
  final bool requireGalleryScope;
  final Future<Uint8List> Function(Uint8List)? rasterizeFirstPage;
  @override
  State<ResourceAttachmentThumbnail> createState() => _ResourceAttachmentThumbnailState();
}

class _ResourceAttachmentThumbnailState extends State<ResourceAttachmentThumbnail> with WidgetsBindingObserver {
  Route<void>? _previewRoute;
  bool _opening = false;
  bool _foreground = false;
  int _openEpoch = 0;
  void _retirePreview() {
    final route = _previewRoute; _previewRoute = null;
    if (route != null) { WidgetsBinding.instance.addPostFrameCallback((_) { if (route.isActive) { route.navigator?.removeRoute(route); } }); }
  }
  @override void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) { _openEpoch++; _retirePreview(); }
  }
  @override void dispose() { _openEpoch++; WidgetsBinding.instance.removeObserver(this); _retirePreview(); super.dispose(); }
  Future<(Uint8List, Uint8List?, bool)>? _content;
  Future<Uint8List>? _original;
  @override
  void initState() {
    super.initState(); _foreground = WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this); _content = _load();
  }
  @override
  void didUpdateWidget(covariant ResourceAttachmentThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.gallery?.source, widget.gallery?.source) ||
        oldWidget.gallery?.workerId != widget.gallery?.workerId ||
        oldWidget.gallery?.companyId != widget.gallery?.companyId ||
        widget.gallery?.isCurrent() == false || oldWidget.attachment.previewKey != widget.attachment.previewKey) { _openEpoch++; _retirePreview(); }
    if (oldWidget.attachment.path != widget.attachment.path ||
        oldWidget.attachment.known != widget.attachment.known) {
      _content = _load();
    }
  }
  Future<(Uint8List, Uint8List?, bool)>? _load() {
    if (!widget.attachment.registered || widget.attachment.loadBytes == null) {
      _original = null;
      return null;
    }
    _original = Future<Uint8List>.sync(widget.attachment.loadBytes!);
    final original = _original!;
    final content = (() async {
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
    // A retry can fail before the next frame attaches FutureBuilder's listener.
    // Observe that error now; the same failed future still drives its error UI.
    content.ignore();
    return content;
  }

  Future<void> _open() async {
    if (_content == null || _opening || !_foreground) return;
    _opening = true;
    final content = _original;
    final selected = widget.attachment, gallery = widget.gallery;
    final path = selected.path, epoch = _openEpoch;
    try {
      if (widget.requireGalleryScope && gallery == null) { throw StateError('Attachment scope unavailable'); }
      if (gallery?.isCurrent() == false) { return; }
      final bytes = await content!;
      if (!mounted || !_foreground || epoch != _openEpoch || gallery?.isCurrent() == false) { return; }
      await selected.validateAccess?.call();
      if (!mounted || !_foreground || epoch != _openEpoch || content != _original || path != widget.attachment.path) return;
      final entries = gallery?.entries ?? [selected];
      final index = gallery?.indexOf(selected) ?? 0;
      bool current() => mounted && _foreground && epoch == _openEpoch &&
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed &&
        content == _original && path == widget.attachment.path && selected.previewKey == widget.attachment.previewKey &&
        (gallery == null || identical(gallery.source, widget.gallery?.source) && gallery.isCurrent());
      if (!current() || index < 0 || index >= entries.length) { return; }
      var closing = false;
      late final DialogRoute<void> route;
      route = DialogRoute<void>(context: context, builder: (previewContext) =>
        _ResourceGalleryViewer(entries: entries, initialIndex: index, initialBytes: bytes,
          defaultTitle: widget.recordTitle, isCurrent: current, changes: gallery?.changes, signal: gallery?.signal, onClose: () {
            if (closing || !route.isCurrent) { return; }
            closing = true; Navigator.of(previewContext).pop();
          }));
      _previewRoute = route;
      await Navigator.of(context).push(route);
      if (identical(_previewRoute, route)) { _previewRoute = null; }
    } catch (_) {
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(SkoLanguageController.tr('添付を表示できませんでした。')),
        action: SnackBarAction(label: SkoLanguageController.tr('再試行'), onPressed: () {
          if (mounted) {
            final reloaded = _load();
            setState(() { _content = reloaded; });
          }
        }))); }
    } finally { _opening = false; }
  }

  @override
  Widget build(BuildContext context) => SizedBox(width: 52, height: (10 * MediaQuery.textScalerOf(context).scale(1) * 1.3 + 47).clamp(80.0, double.infinity).toDouble(),
    child: Column(children: [
      Expanded(child: InkWell(
        onTap: _content == null ? null : _open,
        borderRadius: BorderRadius.circular(6),
        child: Container(width: 52, decoration: BoxDecoration(color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.grey.shade300)),
          child: _content == null ? Center(child: Text(SkoLanguageController.tr(widget.attachment.known ? '未登録' : '未取得'),
            style: const TextStyle(fontSize: 10), textAlign: TextAlign.center))
            : FutureBuilder<(Uint8List, Uint8List?, bool)>(future: _content, builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) { return const Center(
                  child: SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))); }
                if (snapshot.hasError || snapshot.data == null) { return Center(child: Text(SkoLanguageController.tr('読込不可'),
                  style: const TextStyle(fontSize: 10), textAlign: TextAlign.center)); }
                if (snapshot.data!.$2 == null) return const Icon(Icons.picture_as_pdf_outlined, size: 24);
                return ClipRRect(borderRadius: BorderRadius.circular(5), child: Image.memory(
                  snapshot.data!.$2!, cacheWidth: 120, fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Center(child: Text(SkoLanguageController.tr('読込不可'), style: const TextStyle(fontSize: 10)))));
              }),
        ),
      )),
      const SizedBox(height: 3),
      Text(SkoLanguageController.tr(widget.attachment.label), maxLines: 1, overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 10, color: Colors.black54)),
    ]),
  );
}

Future<void> showResourceAttachments(BuildContext context, {
  required String title, required List<ResourceAttachment> attachments,
  ResourceAttachmentGallery? gallery, bool requireGalleryScope = false,
}) => showDialog<void>(context: context, useRootNavigator: false, builder: (context) => Dialog(
  child: Padding(padding: const EdgeInsets.all(16), child: Column(
    mainAxisSize: MainAxisSize.min, children: [
      Text(title, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 12),
      Flexible(child: SingleChildScrollView(child: Wrap(spacing: 12, runSpacing: 12,
        children: [for (final attachment in attachments)
          ResourceAttachmentThumbnail(attachment: attachment, gallery: gallery, recordTitle: title, requireGalleryScope: requireGalleryScope)]))),
      const SizedBox(height: 12),
      TextButton(onPressed: () => Navigator.pop(context), child: Text(SkoLanguageController.tr('閉じる'))),
    ],
  )),
));

class ResourceRegistrationFooter extends StatelessWidget {
  const ResourceRegistrationFooter({super.key, required this.label, required this.onPressed});
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => ColoredBox(color: Colors.white,
    child: SafeArea(top: false, child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: SizedBox(width: double.infinity,
        height: (15 * MediaQuery.textScalerOf(context).scale(1) * 1.3 + 16)
          .clamp(52.0, double.infinity).toDouble(),
        child: FilledButton.icon(onPressed: onPressed,
          icon: const Icon(Icons.note_add_outlined, size: 22),
          label: Text(SkoLanguageController.tr(label), maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          style: FilledButton.styleFrom(shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12))),
        ),
      ),
    )),
  );
}

class ResourceRegistrationOption {
  const ResourceRegistrationOption({required this.id, required this.title});
  final String id, title;
}

Future<String?> chooseRegisteredDocumentRequirement(BuildContext context,
  List<ResourceRegistrationOption> options, {bool Function()? isCurrentScope}) async {
  final selected = await showDialog<String>(
  context: context, builder: (context) => AlertDialog(
    title: Text(SkoLanguageController.tr('登録する書類を選択')),
    content: SizedBox(width: 360, height: 320, child: ListView(
      children: [for (final option in options) ListTile(
        title: Tooltip(message: option.title, child: Text(option.title,
          maxLines: 1, overflow: TextOverflow.ellipsis)),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.pop(context, option.id),
      )],
    )),
    actions: [TextButton(onPressed: () => Navigator.pop(context),
      child: Text(SkoLanguageController.tr('キャンセル')))],
  ),
);
  if (isCurrentScope != null && !isCurrentScope()) { return null; }
  return selected;
}

String resourceDocumentReviewLabel(Object? value) {
  final status = value?.toString() ?? 'not_submitted';
  return switch (status) {
    'not_submitted' => '未提出', 'submitted' => '提出済み',
    'verified' => '確認済み', 'missing' => '不足', 'expired' => '期限切れ',
    _ => status,
  };
}

List<String> resourceQualificationMetadata(Map<String, dynamic> row) => [
  if ((row['expires_at']?.toString() ?? '').isNotEmpty) '期限 ${row['expires_at']}',
  if ((row['issuer']?.toString() ?? '').isNotEmpty) '発行元: ${row['issuer']}',
  if ((row['certificate_number']?.toString() ?? '').isNotEmpty) '証明書 ${row['certificate_number']}',
];


class _ResourceGalleryViewer extends StatefulWidget {
  const _ResourceGalleryViewer({required this.entries, required this.initialIndex,
    required this.initialBytes, required this.isCurrent, required this.onClose, this.defaultTitle, this.changes, this.signal});
  final Stream<Object?>? changes;
  final Listenable? signal;
  final List<ResourceAttachment> entries;
  final int initialIndex;
  final Uint8List initialBytes;
  final String? defaultTitle;
  final bool Function() isCurrent;
  final VoidCallback onClose;
  @override State<_ResourceGalleryViewer> createState() => _ResourceGalleryViewerState();
}
class _ResourceGalleryViewerState extends State<_ResourceGalleryViewer> with WidgetsBindingObserver {
  late final PageController _controller = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;
  bool _active = false;
  StreamSubscription<Object?>? _subscription;
  bool get _current => mounted && _active && WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed && widget.isCurrent();
  @override void initState() {
    super.initState(); _active = WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed; WidgetsBinding.instance.addObserver(this);
    widget.signal?.addListener(_scopeChanged);
    _subscription = widget.changes?.listen((_) { if (!widget.isCurrent()) { _retire(); } },
      onError: (Object error) => _retire(), onDone: _retire);
  }
  void _scopeChanged() { if (!widget.isCurrent()) { _retire(); } }
  void _retire() {
    if (!_active || !mounted) { return; }
    _active = false; setState(() {}); widget.onClose();
  }
  @override void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) { _retire(); }
  }
  @override void dispose() { _active = false; widget.signal?.removeListener(_scopeChanged); final subscription = _subscription; _subscription = null; if (subscription != null) { unawaited(subscription.cancel()); } WidgetsBinding.instance.removeObserver(this); _controller.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) {
    final entry = widget.entries[_index];
    return Dialog.fullscreen(child: Scaffold(resizeToAvoidBottomInset: false,
      appBar: AppBar(toolbarHeight: (56 * MediaQuery.textScalerOf(context).scale(1)).clamp(56.0, 160.0).toDouble(),
        leading: IconButton(tooltip: SkoLanguageController.tr('閉じる'),
        icon: const Icon(Icons.close), onPressed: widget.onClose),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(entry.recordTitle ?? widget.defaultTitle ?? entry.label, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(entry.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
        ]), actions: [Center(child: Padding(padding: const EdgeInsets.only(right: 12), child: Text('${_index + 1}/${widget.entries.length}')))]),
      body: !_current ? const SizedBox.shrink() : PageView.builder(controller: _controller,
        itemCount: widget.entries.length, onPageChanged: (value) {
          if (!_current) { widget.onClose(); return; }
          setState(() => _index = value);
        }, itemBuilder: (_, index) => index != _index ? const SizedBox.expand() : _ResourceGalleryPage(key: ValueKey(widget.entries[index].previewKey ?? index),
          attachment: widget.entries[index], isCurrent: () => _current,
          initialBytes: index == widget.initialIndex ? widget.initialBytes : null)),
    ));
  }
}
class _ResourceGalleryPage extends StatefulWidget {
  const _ResourceGalleryPage({super.key, required this.attachment, required this.isCurrent, this.initialBytes});
  final ResourceAttachment attachment;
  final bool Function() isCurrent;
  final Uint8List? initialBytes;
  @override State<_ResourceGalleryPage> createState() => _ResourceGalleryPageState();
}
class _ResourceGalleryPageState extends State<_ResourceGalleryPage> {
  late final Future<Uint8List> _bytes = _load();
  Future<Uint8List> _load() async {
    if (!widget.isCurrent()) { throw StateError('Attachment scope changed'); }
    await widget.attachment.validateAccess?.call();
    if (!mounted || !widget.isCurrent()) { throw StateError('Attachment scope changed'); }
    final bytes = widget.initialBytes ?? await widget.attachment.loadBytes!();
    if (!mounted || !widget.isCurrent()) { throw StateError('Attachment scope changed'); }
    await widget.attachment.validateAccess?.call();
    if (!mounted || !widget.isCurrent() || bytes.isEmpty) { throw StateError('Attachment scope changed'); }
    return bytes;
  }
  @override Widget build(BuildContext context) => FutureBuilder<Uint8List>(future: _bytes, builder: (context, snapshot) {
    if (!widget.isCurrent()) { return const SizedBox.shrink(); }
    if (snapshot.hasError) { return Center(child: Text(SkoLanguageController.tr('添付を表示できませんでした。'))); }
    final bytes = snapshot.data;
    if (bytes == null) { return const Center(child: CircularProgressIndicator()); }
    if (_isPdf(bytes)) {
      Future<Uint8List> buildPreviewPdf(PdfPageFormat _) async {
        if (!mounted || !widget.isCurrent()) { throw StateError('Attachment scope changed'); }
        return bytes;
      }
      return PdfPreview.builder(build: buildPreviewPdf, pagesBuilder: (_, pages) => PdfPinchPages(pages: pages), useActions: true,
        canDebug: false, canChangeOrientation: false, canChangePageFormat: false,
        allowPrinting: true, allowSharing: false, dynamicLayout: false,
        onError: (_, __) => Center(child: Text(SkoLanguageController.tr('PDFを表示できませんでした。'))));
    }
    return Center(child: InteractiveViewer(minScale: .5, maxScale: 5,
      child: Image.memory(bytes, fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Text(SkoLanguageController.tr('画像を表示できませんでした。')))));
  });
}
