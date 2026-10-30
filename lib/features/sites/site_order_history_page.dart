import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'site_order_workflow.dart';

/// History metadata and bytes come exclusively from the protected archive RPC.
/// The adapter owns paging and access checks; a file URL is never a site field.
class SiteOrderHistoryPage extends StatefulWidget {
  const SiteOrderHistoryPage({super.key, required this.orders,
    required this.requireScope, required this.scopeChanges, required this.loadPdf});
  final List<SiteOrderArtifact> orders;
  final VoidCallback requireScope;
  final Listenable scopeChanges;
  final Future<Uint8List> Function(SiteOrderArtifact) loadPdf;
  @override
  State<SiteOrderHistoryPage> createState() => _SiteOrderHistoryPageState();
}

class _SiteOrderHistoryPageState extends State<SiteOrderHistoryPage> {
  bool _retired = false;
  @override
  void initState() { super.initState(); widget.scopeChanges.addListener(_check); _check(); }
  void _check() {
    try { widget.requireScope(); } catch (_) {
      if (mounted) setState(() => _retired = true);
    }
  }
  @override
  void dispose() { widget.scopeChanges.removeListener(_check); super.dispose(); }
  Future<void> _open(int index) async {
    try {
      widget.requireScope();
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) =>
        SiteOrderArchivePreviewPage(orders: List.unmodifiable(widget.orders),
          initialIndex: index, requireScope: widget.requireScope,
          scopeChanges: widget.scopeChanges, loadPdf: widget.loadPdf)));
      widget.requireScope();
    } catch (_) { if (mounted) setState(() => _retired = true); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('過去の注文書')),
    body: _retired ? const Center(child: Text('開き直してください。'))
      : widget.orders.isEmpty ? const Center(child: Text('保存された注文書はありません。'))
      : ListView.builder(itemCount: widget.orders.length, itemBuilder: (context, index) {
        final order = widget.orders[index];
        return ListTile(title: Text(order.title), subtitle: Text(order.period),
          trailing: const Icon(Icons.chevron_right), onTap: () => _open(index));
      }));
}

class SiteOrderArchivePreviewPage extends StatefulWidget {
  const SiteOrderArchivePreviewPage({super.key, required this.orders,
    required this.initialIndex, required this.requireScope,
    required this.scopeChanges, required this.loadPdf});
  final List<SiteOrderArtifact> orders;
  final int initialIndex;
  final VoidCallback requireScope;
  final Listenable scopeChanges;
  final Future<Uint8List> Function(SiteOrderArtifact) loadPdf;
  @override
  State<SiteOrderArchivePreviewPage> createState() => _SiteOrderArchivePreviewPageState();
}

class _SiteOrderArchivePreviewPageState extends State<SiteOrderArchivePreviewPage> {
  late final PageController _pages;
  late int _index;
  bool _retired = false;
  bool _zoomed = false;
  @override
  void initState() {
    super.initState();
    if (widget.orders.isEmpty || widget.initialIndex < 0 || widget.initialIndex >= widget.orders.length) {
      throw ArgumentError('注文書を選択してください。');
    }
    _index = widget.initialIndex;
    _pages = PageController(initialPage: _index);
    widget.scopeChanges.addListener(_check);
    _check();
  }
  void _check() {
    try { widget.requireScope(); } catch (_) {
      if (mounted) setState(() => _retired = true);
    }
  }
  @override
  void dispose() { widget.scopeChanges.removeListener(_check); _pages.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(automaticallyImplyLeading: false,
      title: _retired ? const Text('注文書') : Text(widget.orders[_index].title),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('閉じる'))]),
    body: SafeArea(child: _retired ? const Center(child: Text('開き直してください。'))
      : Column(children: [
        Text(widget.orders[_index].period),
        Text('${_index + 1} / ${widget.orders.length}件'),
        Expanded(child: PageView.builder(controller: _pages,
          physics: _zoomed ? const NeverScrollableScrollPhysics() : null,
          itemCount: widget.orders.length,
          onPageChanged: (index) { _check(); if (!_retired) setState(() => _index = index); },
          itemBuilder: (_, index) => _ArchivedOrderPdf(key: ValueKey(widget.orders[index].fingerprint),
            order: widget.orders[index], requireScope: widget.requireScope,
            onZoomChanged: (zoomed) { if (mounted) setState(() => _zoomed = zoomed); },
            loadPdf: widget.loadPdf))),
      ])));
}

class _ArchivedOrderPdf extends StatefulWidget {
  const _ArchivedOrderPdf({super.key, required this.order,
    required this.requireScope, required this.loadPdf, required this.onZoomChanged});
  final SiteOrderArtifact order;
  final VoidCallback requireScope;
  final Future<Uint8List> Function(SiteOrderArtifact) loadPdf;
  final ValueChanged<bool> onZoomChanged;
  @override
  State<_ArchivedOrderPdf> createState() => _ArchivedOrderPdfState();
}

class _ArchivedOrderPdfState extends State<_ArchivedOrderPdf> {
  List<Uint8List>? _images;
  String? _error;
  final _transform = TransformationController();
  bool _zoomed = false;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try {
      widget.requireScope();
      final bytes = await widget.loadPdf(widget.order);
      widget.requireScope();
      if (bytes.length > 20 * 1024 * 1024 ||
          sha256.convert(bytes).toString() != widget.order.pdfSha256) {
        throw StateError('保存された注文書とPDFが一致しません。');
      }
      final images = <Uint8List>[];
      await for (final page in Printing.raster(bytes, dpi: 120)) {
        widget.requireScope();
        if (!mounted) return;
        if (images.length >= 12) throw StateError('注文書のページ数を確認できません。');
        images.add(await page.toPng());
        widget.requireScope();
      }
      if (images.isEmpty) throw StateError('注文書を表示できません。');
      if (mounted) setState(() => _images = images);
    } catch (_) {
      if (mounted) setState(() { _images = null; _error = '注文書を表示できません。一覧から開き直してください。'; });
    }
  }
  @override
  void dispose() { _transform.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    if (_error != null) return Center(child: Text(_error!));
    if (_images == null) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      if (_zoomed) TextButton(onPressed: () {
        _transform.value = Matrix4.identity();
        setState(() => _zoomed = false); widget.onZoomChanged(false);
      }, child: const Text('全体表示に戻す')),
      Expanded(child: InteractiveViewer(transformationController: _transform,
      minScale: 1, maxScale: 8, panEnabled: _zoomed,
      onInteractionUpdate: (_) {
        final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
        if (zoomed != _zoomed) {
          setState(() => _zoomed = zoomed); widget.onZoomChanged(zoomed);
        }
      },
      child: ListView.builder(itemCount: _images!.length,
        itemBuilder: (_, index) => Image.memory(_images![index], fit: BoxFit.contain)))),
    ]);
  }
}
