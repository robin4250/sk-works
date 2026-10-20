import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../domain/company_seal_snapshot.dart';
import '../../domain/company_uploaded_seal_png.dart';
import '../shared/company_seal_pdf.dart';
import '../shared/pdf_pinch_pages.dart';
import '../shared/trade_document_actor_boundary.dart';
import 'company_seal_png_repository.dart';

class CompanySealPngUploader extends StatefulWidget {
  const CompanySealPngUploader({super.key, required this.company, this.source, this.pickPng});
  final UploadedSealCompany company;
  final CompanySealPngSource? source;
  @visibleForTesting final Future<Uint8List?> Function()? pickPng;
  @override State<CompanySealPngUploader> createState() => _CompanySealPngUploaderState();
}
class _CompanySealPngUploaderState extends State<CompanySealPngUploader> {
  late final _source = widget.source ?? CompanySealPngRepository.maybeCreate();
  CompanySealPngSettings? _settings;
  CompanyUploadedSealPng? _pending;
  String? _previewedHash, _error;
  bool _busy = true;
  int _generation = 0;
  @override void initState() { super.initState(); _load(); }
  @override void didUpdateWidget(covariant CompanySealPngUploader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.company != widget.company) _load();
  }
  @override void dispose() { _generation++; super.dispose(); }
  Future<void> _load() async {
    final generation = ++_generation;
    final company = widget.company;
    setState(() { _busy = true; _error = null; _settings = null; _pending = null; _previewedHash = null; });
    try {
      final result = await _source?.load(company) ?? CompanySealPngSettings(company: company, available: false);
      if (!mounted || generation != _generation) return;
      setState(() => _settings = result);
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _error = 'PNG角印の設定を読み込めませんでした。');
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }
  Future<void> _pick() async {
    if (_busy || _settings?.available != true) return;
    final generation = _generation;
    setState(() { _busy = true; _error = null; });
    try {
      Uint8List? bytes;
      if (widget.pickPng != null) {
        bytes = await widget.pickPng!();
      } else {
        final result = await FilePicker.platform.pickFiles(type: FileType.custom,
          allowedExtensions: ['png'], allowMultiple: false, withData: true);
        if (result == null) return;
        bytes = result.files.single.bytes;
        if (bytes == null) throw StateError('PNGの読込に失敗しました。');
      }
      if (bytes == null) return;
      final png = CompanyUploadedSealPng.fromBytes(bytes);
      final codec = await ui.instantiateImageCodec(png.bytes);
      try {
        final frame = await codec.getNextFrame();
        try {
          if (codec.frameCount != 1 || frame.image.width != png.width || frame.image.height != png.height) {
            throw StateError('静止画PNGを選択してください。');
          }
        } finally { frame.image.dispose(); }
      } finally { codec.dispose(); }
      if (!mounted || generation != _generation) return;
      setState(() { _pending = png; _previewedHash = null; });
    } catch (e) {
      if (mounted && generation == _generation) setState(() => _error = e is FormatException ? e.message : 'PNG画像を読み込めませんでした。');
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }
  Future<void> _preview() async {
    final png = _pending ?? _settings?.png;
    if (_busy || png == null) return;
    final generation = _generation, company = widget.company;
    final actorLease = TradeDocumentActorLease();
    setState(() { _busy = true; _error = null; });
    try {
      final font = await CompanySealPdf.loadFont();
      final doc = pw.Document();
      doc.addPage(pw.Page(pageFormat: PdfPageFormat.a4, build: (_) => pw.Column(children: [
        pw.Text(company.name, style: pw.TextStyle(font: font)), pw.SizedBox(height: 24),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly, children: [
          for (final size in [32.0, 42.0, 55.0]) CompanySealPdf.build(company.name,
            style: CompanySealSnapshot.uploadedStyle, companyId: company.companyId,
            uploadedPng: png, size: size),
        ]),
      ])));
      final bytes = await doc.save();
      actorLease.verify();
      if (!mounted || generation != _generation) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TradeDocumentActorBoundary(child: Scaffold(
        appBar: AppBar(title: const Text('登録PNGの角印プレビュー')),
        body: PdfPreview.builder(pagesBuilder: (_, pages) => PdfPinchPages(pages: pages),
          build: (_) async => bytes, allowPrinting: true, allowSharing: true,
          canChangePageFormat: false, canChangeOrientation: false),
      ))));
      actorLease.verify();
      if (mounted && generation == _generation) setState(() => _previewedHash = png.sha256);
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _error = 'PNG角印をプレビューできませんでした。');
    } finally {
      actorLease.dispose();
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }
  Future<void> _save(bool enabled) async {
    final settings = _settings;
    final png = _pending ?? settings?.png;
    if (_busy || settings == null || !settings.available || _source == null ||
        (enabled && (png == null || _previewedHash != png.sha256))) return;
    final generation = _generation;
    setState(() { _busy = true; _error = null; });
    try {
      final result = await _source!.save(settings, png: enabled ? _pending : null, enabled: enabled);
      if (!mounted || generation != _generation) return;
      setState(() { _settings = result; _pending = null; _previewedHash = null; });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(enabled
        ? 'PNG角印を保存しました。新しく保存する帳票に反映します。' : '登録PNGの使用をOFFにしました。')));
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _error = 'PNG角印を保存できませんでした。再読み込みして確認してください。');
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }
  @override Widget build(BuildContext context) {
    final png = _pending ?? _settings?.png;
    final available = _settings?.available == true;
    return Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('PNGの角印を登録', style: TextStyle(fontWeight: FontWeight.bold)),
        const Text('会社専用のPNGを選び、プレビューして保存します。過去の帳票の印影は変わりません。'),
        if (_busy) const LinearProgressIndicator(),
        if (!_busy && _settings != null && !available) const Text('PNG登録の保存準備中です。既存の角印は引き続き使えます。'),
        if (png != null) Image.memory(png.bytes, height: 120, fit: BoxFit.contain),
        if (_settings?.enabled == true) const Text('新しい帳票には登録PNGを使用中です。下のデザインへ戻す場合はPNGをOFFにしてください。'),
        OutlinedButton.icon(onPressed: _busy || !available ? null : _pick,
          icon: const Icon(Icons.upload_file), label: const Text('PNGファイルを選ぶ')),
        const Text('1MB以下・32〜2048px・RGB/RGBAの静止画PNG。透過背景を推奨します。'),
        OutlinedButton(onPressed: _busy || png == null ? null : _preview,
          child: const Text('登録PNGをプレビュー')),
        FilledButton(onPressed: _busy || !available || png == null || _previewedHash != png.sha256
          ? null : () => _save(true), child: const Text('このPNGを保存して使用')),
        if (_settings?.enabled == true) TextButton(onPressed: _busy ? null : () => _save(false),
          child: const Text('登録PNGの使用をOFF')),
        if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        if (_error != null) TextButton(onPressed: _busy ? null : _load, child: const Text('再読み込み')),
      ],
    )));
  }
}
