import 'dart:typed_data';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

// Raster/pinch code ported from reviewed PR1629 head4a7144a5d4b376c33ae54b7c1a01324fe2f57388.
// The read-only DTO carries no fabricated price or site/stamp version.
class _ArchivedOrderPdf extends StatefulWidget {
  const _ArchivedOrderPdf({
    super.key,
    required this.pdfSha256,
    required this.requireScope,
    required this.loadPdf,
    required this.onZoomChanged,
  });
  final String pdfSha256;
  final VoidCallback requireScope;
  final Future<Uint8List> Function() loadPdf;
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
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      widget.requireScope();
      final bytes = await widget.loadPdf();
      widget.requireScope();
      if (bytes.length > 20 * 1024 * 1024 ||
          sha256.convert(bytes).toString() != widget.pdfSha256) {
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
      if (mounted) {
        setState(() {
          _images = null;
          _error = '注文書を表示できません。一覧から開き直してください。';
        });
      }
    }
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Center(child: Text(_error!));
    if (_images == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        if (_zoomed)
          TextButton(
            onPressed: () {
              _transform.value = Matrix4.identity();
              setState(() => _zoomed = false);
              widget.onZoomChanged(false);
            },
            child: const Text('全体表示に戻す'),
          ),
        Expanded(
          child: InteractiveViewer(
            transformationController: _transform,
            minScale: 1,
            maxScale: 8,
            panEnabled: _zoomed,
            onInteractionUpdate: (_) {
              final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
              if (zoomed != _zoomed) {
                setState(() => _zoomed = zoomed);
                widget.onZoomChanged(zoomed);
              }
            },
            child: ListView.builder(
              itemCount: _images!.length,
              itemBuilder: (_, index) =>
                  Image.memory(_images![index], fit: BoxFit.contain),
            ),
          ),
        ),
      ],
    );
  }
}

/// Read-only history has no fabricated unit prices, site mappings or stamp
/// versions. The protected archive supplies an exact saved UUID and byte hash.
class SiteOrderSavedEntry {
  SiteOrderSavedEntry({
    required this.packageId,
    required this.title,
    required this.startsOn,
    required this.endsOn,
    required this.pdfSha256,
  }) {
    if (!RegExp(r'^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$')
            .hasMatch(packageId) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(pdfSha256)) {
      throw const FormatException('保存された原本を確認できません。');
    }
  }
  final String packageId, title, startsOn, endsOn, pdfSha256;
  String get displayTitle => title.trim().isEmpty ? '工事名称未設定' : title;
  String get period =>
      startsOn.isEmpty && endsOn.isEmpty ? '工期未設定' : '$startsOn ～ $endsOn';
  String get fingerprint =>
      jsonEncode([packageId, pdfSha256, title, startsOn, endsOn]);
}

/// Reuses the existing bounded/hash-checked raster and pinch viewer above.
class SiteOrderSavedPreviewPager extends StatefulWidget {
  const SiteOrderSavedPreviewPager({
    super.key,
    required this.entries,
    required this.initialIndex,
    required this.requireScope,
    required this.scopeChanges,
    required this.loadPdf,
    this.loadMore,
    this.hasMore = false,
    this.openOutput,
    this.entryBuilder,
  });
  final List<SiteOrderSavedEntry> entries;
  final int initialIndex;
  final VoidCallback requireScope;
  final Listenable scopeChanges;
  final Future<Uint8List> Function(SiteOrderSavedEntry) loadPdf;
  final Future<List<SiteOrderSavedEntry>> Function()? loadMore;
  final bool hasMore;
  final void Function(SiteOrderSavedEntry)? openOutput;
  @visibleForTesting
  final Widget Function(SiteOrderSavedEntry)? entryBuilder;
  @override
  State<SiteOrderSavedPreviewPager> createState() =>
      _SiteOrderSavedPreviewPagerState();
}

class _SiteOrderSavedPreviewPagerState
    extends State<SiteOrderSavedPreviewPager> {
  late final PageController _controller;
  late final List<SiteOrderSavedEntry> _entries;
  late int _index;
  late bool _more;
  bool _retired = false, _zoomed = false, _loading = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    if (widget.entries.isEmpty ||
        widget.initialIndex < 0 ||
        widget.initialIndex >= widget.entries.length) {
      throw ArgumentError('保存された注文書を選択してください。');
    }
    _entries = List.of(widget.entries);
    _index = widget.initialIndex;
    _more = widget.hasMore;
    _controller = PageController(initialPage: _index);
    widget.scopeChanges.addListener(_check);
    _check();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_retired && _more && _index == _entries.length - 1) {
        _next();
      }
    });
  }

  void _check() {
    try {
      widget.requireScope();
    } catch (_) {
      if (mounted) setState(() => _retired = true);
    }
  }

  Future<void> _next() async {
    if (_loading || !_more || widget.loadMore == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      widget.requireScope();
      final values = await widget.loadMore!();
      widget.requireScope();
      if (!mounted || _retired) return;
      final known = _entries.map((e) => e.packageId).toSet();
      if (values.any((e) => !known.add(e.packageId))) {
        throw StateError('履歴の保存版が変わりました。');
      }
      setState(() {
        _entries.addAll(values);
        _more = values.length == 50;
      });
    } catch (_) {
      if (mounted) setState(() => _error = '続きの履歴を確認できません。');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    widget.scopeChanges.removeListener(_check);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        tooltip: '閉じる',
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.close),
      ),
      title: Text(_retired ? '注文書' : _entries[_index].displayTitle),
      actions: [
        if (!_retired && widget.openOutput != null)
          IconButton(
            tooltip: '印刷・保存',
            icon: const Icon(Icons.print_outlined),
            onPressed: () {
              _check();
              if (!_retired) widget.openOutput!(_entries[_index]);
            },
          ),
      ],
    ),
    body: _retired
        ? const Center(child: Text('画面を閉じて開き直してください。'))
        : Column(
            children: [
              Text(
                '${_entries[_index].period}   ${_index + 1} / ${_entries.length}件',
              ),
              if (_loading) const LinearProgressIndicator(),
              if (_error != null)
                TextButton(onPressed: _next, child: Text('$_error  再確認')),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  physics: _zoomed
                      ? const NeverScrollableScrollPhysics()
                      : null,
                  itemCount: _entries.length,
                  onPageChanged: (index) {
                    _check();
                    if (!_retired) {
                      setState(() => _index = index);
                      if (_entries.length - index <= 2) _next();
                    }
                  },
                  itemBuilder: (_, index) =>
                      widget.entryBuilder?.call(_entries[index]) ??
                      _ArchivedOrderPdf(
                        key: ValueKey(_entries[index].fingerprint),
                        pdfSha256: _entries[index].pdfSha256,
                        requireScope: widget.requireScope,
                        loadPdf: () => widget.loadPdf(_entries[index]),
                        onZoomChanged: (value) {
                          if (mounted) setState(() => _zoomed = value);
                        },
                      ),
                ),
              ),
            ],
          ),
  );
}
