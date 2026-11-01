import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../shared/pdf_pinch_pages.dart';
import '../shared/standalone_trade_document_print_scope.dart';
import '../shared/trade_document_form_renderer.dart';
import '../shared/trade_document_output_layout.dart';
import '../shared/trade_document_output_selector.dart';
import 'site_order_workflow_repository.dart';

/// Original bytes only. Derivatives use the same frozen server payload; a
/// review draft never reaches this screen or the native export callbacks.
class SiteOrderWorkflowPdfPage extends StatefulWidget {
  const SiteOrderWorkflowPdfPage({
    super.key,
    required this.api,
    required this.packageId,
    required this.title,
    this.kind = 'order',
    this.previewBuilder,
    this.outputBuilder,
  });
  final SiteOrderWorkflowApi api;
  final String packageId, title, kind;
  @visibleForTesting
  final Widget Function(Uint8List)? previewBuilder;
  @visibleForTesting
  final Future<Uint8List> Function(
    Map<String, dynamic>,
    TradeDocumentOutputLayout,
    Uint8List,
  )?
  outputBuilder;
  @override
  State<SiteOrderWorkflowPdfPage> createState() =>
      _SiteOrderWorkflowPdfPageState();
}

class _SiteOrderWorkflowPdfPageState extends State<SiteOrderWorkflowPdfPage>
    with WidgetsBindingObserver {
  Uint8List? _bytes, _previewBytes, _exportBytes;
  TradeDocumentOutputLayout _layout = TradeDocumentOutputLayout.a4TwoPages;
  int _layoutGeneration = 0;
  Map<String, dynamic>? _payload;
  bool _busy = false, _disposing = false, _viewRetired = false;
  String? _error;
  late final StandaloneTradeDocumentPrintScope _print;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.api.addListener(_scopeChanged);
    _print = StandaloneTradeDocumentPrintScope(
      verifyScope: () {
        if (!mounted) throw StateError('画面が閉じられました。');
        widget.api.requireCurrent();
      },
      currentBytes: () => _exportBytes,
      currentTarget: () => '${widget.packageId}:${widget.kind}',
      onRevoke: _clear,
    );
    _load();
  }

  void _clear() {
    _layoutGeneration++;
    _bytes = null;
    _previewBytes = null;
    _exportBytes = null;
    _payload = null;
    _viewRetired = true;
    if (mounted && !_disposing) setState(() {});
  }

  void _scopeChanged() {
    if (widget.api.invalidated) _print.invalidate();
  }

  Future<void> _load() async {
    try {
      final bytes = await widget.api.original(widget.packageId, widget.kind);
      if (mounted && !widget.api.invalidated && !_viewRetired) {
        setState(() {
          _bytes = bytes;
          _previewBytes = bytes;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = '保存済み原本を確認できません。閉じて開き直してください。');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    try {
      _print.visibilityChanged(switch (state) {
        AppLifecycleState.resumed => StandalonePrintVisibility.resumed,
        AppLifecycleState.inactive => StandalonePrintVisibility.inactive,
        AppLifecycleState.hidden => StandalonePrintVisibility.hidden,
        AppLifecycleState.paused => StandalonePrintVisibility.paused,
        AppLifecycleState.detached => StandalonePrintVisibility.detached,
      });
    } catch (_) {
      _clear();
    }
  }

  Future<void> _selectLayout(TradeDocumentOutputLayout layout) async {
    final original = _bytes;
    if (_busy || original == null || layout == _layout) return;
    final generation = ++_layoutGeneration;
    setState(() => _busy = true);
    try {
      await widget.api.verify();
      Uint8List output = original;
      if (layout != TradeDocumentOutputLayout.a4TwoPages) {
        final payload =
            _payload ??
            await widget.api.originalPayload(widget.packageId, widget.kind);
        await widget.api.verify();
        if (!mounted ||
            _viewRetired ||
            generation != _layoutGeneration ||
            !identical(_bytes, original)) {
          return;
        }
        _payload = payload;
        output = widget.outputBuilder != null
            ? await widget.outputBuilder!(_payload!, layout, original)
            : await TradeDocumentFormRenderer.output(
                _payload!,
                layout: layout,
                canonicalBytes: original,
              );
      }
      await widget.api.verify();
      if (!mounted ||
          _viewRetired ||
          generation != _layoutGeneration ||
          !identical(_bytes, original)) {
        return;
      }
      setState(() {
        _layout = layout;
        _previewBytes = output;
      });
    } catch (_) {
      if (mounted && !_viewRetired) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('選んだ形式を確認できません。A4原本を選ぶか、原本を開き直してください。')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _output(bool share) async {
    final original = _bytes;
    final output = _previewBytes;
    if (_busy || original == null || output == null) return;
    setState(() => _busy = true);
    try {
      await widget.api.verify();
      if (!mounted ||
          _viewRetired ||
          !identical(_bytes, original) ||
          !identical(_previewBytes, output)) {
        throw StateError('原本が変わりました。');
      }
      _exportBytes = output;
      _print.begin(output);
      if (share) {
        await Printing.sharePdf(
          bytes: _print.layout(),
          filename: 'SKO-${widget.kind}.pdf',
        );
      } else {
        await Printing.layoutPdf(
          onLayout: (_) async {
            await widget.api.verify();
            return _print.layout();
          },
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('出力を確認できません。A4原本を選ぶか、原本を開き直してください。')),
        );
      }
    } finally {
      try {
        _print.end();
      } catch (_) {
        _clear();
      }
      _exportBytes = null;
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _disposing = true;
    widget.api.removeListener(_scopeChanged);
    WidgetsBinding.instance.removeObserver(this);
    _print.invalidate();
    _bytes = null;
    _previewBytes = null;
    _payload = null;
    _exportBytes = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        tooltip: '閉じる',
        icon: const Icon(Icons.close),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text(widget.title),
      actions: [
        IconButton(
          tooltip: '印刷',
          onPressed: _busy || _bytes == null ? null : () => _output(false),
          icon: const Icon(Icons.print_outlined),
        ),
        IconButton(
          tooltip: '保存・共有',
          onPressed: _busy || _bytes == null ? null : () => _output(true),
          icon: const Icon(Icons.ios_share),
        ),
      ],
    ),
    body: widget.api.invalidated || _viewRetired
        ? const Center(child: Text('ログイン・会社の状態が変わりました。閉じて開き直してください。'))
        : _error != null
        ? Center(child: Text(_error!))
        : _bytes == null
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: TradeDocumentOutputSelector(
                  key: ValueKey((_layout, _layoutGeneration)),
                  value: _layout,
                  enabled: !_busy,
                  onChanged: _selectLayout,
                ),
              ),
              if (_busy) const LinearProgressIndicator(),
              Expanded(
                child:
                    widget.previewBuilder?.call(_previewBytes!) ??
                    PdfPreview.builder(
                      key: ValueKey(_layout),
                      build: (_) async {
                        widget.api.requireCurrent();
                        return _previewBytes!;
                      },
                      allowPrinting: false,
                      allowSharing: false,
                      canChangeOrientation: false,
                      canChangePageFormat: false,
                      canDebug: false,
                      pagesBuilder: (context, pages) =>
                          PdfPinchPages(pages: pages),
                    ),
              ),
            ],
          ),
  );
}
