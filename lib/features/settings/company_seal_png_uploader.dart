import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../domain/company_seal_snapshot.dart';
import '../../data/supabase_backend.dart';
import 'company_seal_image_import.dart';
import 'company_seal_image_editor_page.dart';
import 'company_seal_image_versions_repository.dart';
import '../../domain/company_uploaded_seal_png.dart';
import '../shared/company_seal_pdf.dart';
import '../shared/pdf_pinch_pages.dart';
import '../shared/trade_document_actor_boundary.dart';
import 'company_seal_png_repository.dart';

class CompanySealPngUploader extends StatefulWidget {
  const CompanySealPngUploader({super.key, required this.company, this.source, this.pickPng, this.versionsForTesting});
  final UploadedSealCompany company;
  final CompanySealPngSource? source;
  @visibleForTesting final CompanySealImageVersionsRepository? versionsForTesting;
  @visibleForTesting final Future<Uint8List?> Function()? pickPng;
  @override State<CompanySealPngUploader> createState() => _CompanySealPngUploaderState();
}
class _CompanySealPngUploaderState extends State<CompanySealPngUploader> {
  late final _source = widget.source ?? CompanySealPngRepository.maybeCreate();
  CompanySealPngSettings? _settings;
  CompanyUploadedSealPng? _pending;
  String? _previewedHash, _error;
  CompanySealImageVersionsRepository? get _versions => widget.versionsForTesting ?? (SupabaseBackend.isInitialized && SupabaseBackend.client.auth.currentUser != null
      ? CompanySealImageVersionsRepository(SupabaseBackend.client) : null);
  bool _toolsAllowed = false, _extendedCandidate = false;
  String? _registeredHash;
  List<CompanySealImageVersion> _history = const [];
  bool _moreHistory = false, _historyLoaded = false;
  bool _busy = true;
  int _generation = 0;
  @override void initState() { super.initState(); _load(); }
  @override void didUpdateWidget(covariant CompanySealPngUploader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.company != widget.company) { _load(); }
  }
  @override void dispose() { _generation++; super.dispose(); }
  Future<void> _load() async {
    final generation = ++_generation;
    final company = widget.company;
    setState(() { _busy = true; _error = null; _historyLoaded = false; _history = const []; _moreHistory = false; _settings = null; _pending = null; _previewedHash = null; });
    try {
      final result = await _source?.load(company) ?? CompanySealPngSettings(company: company, available: false);
      if (!mounted || generation != _generation) { return; }
      final tools = await _canEdit();
      if (!mounted || generation != _generation) { return; }
      setState(() { _settings = result; _toolsAllowed = tools; _extendedCandidate = false; _registeredHash = null; _history = const []; });
    } catch (_) {
      if (mounted && generation == _generation) { setState(() => _error = 'PNG角印の設定を読み込めませんでした。'); }
    } finally {
      if (mounted && generation == _generation) { setState(() => _busy = false); }
    }
  }
  Future<void> _pick() async {
    if (_busy || _settings?.available != true) { return; }
    if (_toolsAllowed && widget.pickPng == null) {
      await _import(SealImportKind.file);
      return;
    }
    final generation = _generation;
    setState(() { _busy = true; _error = null; });
    try {
      Uint8List? bytes;
      if (widget.pickPng != null) {
        bytes = await widget.pickPng!();
      } else {
        final file = await FilePicker.pickFile(type: FileType.custom,
          allowedExtensions: const ['png']);
        if (file == null) { return; }
        final length = await file.length();
        if (length != null && length > CompanyUploadedSealPng.maxBytes) {
          throw const FormatException('角印PNGは1MB以下にしてください。');
        }
        bytes = Uint8List.fromList(await file.readAsBytes());
      }
      if (bytes == null) { return; }
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
      if (!mounted || generation != _generation) { return; }
      setState(() { _pending = png; _previewedHash = null; _extendedCandidate = false; _registeredHash = null; });
    } catch (e) {
      if (mounted && generation == _generation) { setState(() => _error = e is FormatException ? e.message : 'PNG画像を読み込めませんでした。'); }
    } finally {
      if (mounted && generation == _generation) { setState(() => _busy = false); }
    }
  }

  Future<bool> _canEdit() async {
    try { return await _versions?.allowed() ?? false; } catch (_) { return false; }
  }
  Future<void> _import(SealImportKind kind) async {
    if (_busy || !_toolsAllowed || _settings?.available != true) { return; }
    final generation = _generation;
    final lease = TradeDocumentActorLease();
    setState(() { _busy = true; _error = null; });
    try {
      if (!await _canEdit()) { throw StateError('角印の画像編集は現在利用できません。'); }
      final input = await pickCompanySealInput(kind);
      lease.verify();
      if (input == null || !mounted || generation != _generation) { return; }
      final candidate = await Navigator.of(context).push<CompanyUploadedSealPng>(
        MaterialPageRoute(builder: (_) => TradeDocumentActorBoundary(
          child: CompanySealImageEditorPage(input: input, canEdit: _canEdit))));
      lease.verify();
      final allowed = await _canEdit();
      lease.verify();
      if (candidate == null || !mounted || generation != _generation || !allowed) { return; }
      setState(() {
        _pending = candidate; _previewedHash = null;
        _extendedCandidate = true; _registeredHash = null;
      });
    } catch (error) {
      if (mounted && generation == _generation) { setState(() => _error = '$error'); }
    } finally {
      lease.dispose();
      if (mounted && generation == _generation) { setState(() => _busy = false); }
    }
  }
  Future<void> _register() async {
    final png = _pending;
    final versions = _versions;
    if (_busy || png == null || versions == null || _previewedHash != png.sha256) { return; }
    final generation = _generation, company = widget.company;
    setState(() { _busy = true; _error = null; _historyLoaded = false; });
    try {
      await versions.register(company, png);
      if (!mounted || generation != _generation) { return; }
      setState(() { _registeredHash = png.sha256; _extendedCandidate = true; _historyLoaded = false; });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:
        Text('角印を追加保存しました。使用中の印影は変わりません。「この印影を使用」で切り替えます。')));
    } catch (_) {
      if (mounted && generation == _generation) { setState(() => _error = '角印を追加保存できませんでした。保存準備または機能設定を確認してください。'); }
    } finally {
      if (mounted && generation == _generation) { setState(() => _busy = false); }
    }
  }
  Future<void> _loadHistory({bool older = false}) async {
    final versions = _versions;
    if (_busy || versions == null || !_toolsAllowed) { return; }
    final generation = _generation, company = widget.company;
    setState(() { _busy = true; _error = null; _historyLoaded = false; });
    try {
      final rows = await versions.list(company, before: older && _history.isNotEmpty ? _history.last : null);
      if (!mounted || generation != _generation) { return; }
      setState(() { _history = older ? [..._history, ...rows] : rows; _moreHistory = rows.length == 20; _historyLoaded = true; });
    } catch (_) {
      if (mounted && generation == _generation) { setState(() => _error = '角印の履歴を読み込めません。追加保存の準備を確認してください。'); }
    } finally {
      if (mounted && generation == _generation) { setState(() => _busy = false); }
    }
  }
  Future<void> _chooseVersion(CompanySealImageVersion version) async {
    final versions = _versions;
    if (_busy || versions == null) { return; }
    final generation = _generation;
    setState(() { _busy = true; _error = null; });
    try {
      final png = await versions.read(version);
      if (!mounted || generation != _generation) { return; }
      setState(() {
        _pending = png; _extendedCandidate = true;
        _registeredHash = png.sha256; _previewedHash = null;
      });
    } catch (_) {
      if (mounted && generation == _generation) { setState(() => _error = '選択した角印を読み込めませんでした。'); }
    } finally {
      if (mounted && generation == _generation) { setState(() => _busy = false); }
    }
  }

  Future<void> _preview() async {
    final png = _pending ?? _settings?.png;
    if (_busy || png == null) { return; }
    final generation = _generation, company = widget.company;
    final actorLease = TradeDocumentActorLease();
    setState(() { _busy = true; _error = null; });
    try {
      if (_extendedCandidate && !await _canEdit()) {
        throw StateError('角印の画像編集は現在利用できません。');
      }
      actorLease.verify();
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
      if (_extendedCandidate && !await _canEdit()) {
        throw StateError('角印の画像編集は現在利用できません。');
      }
      actorLease.verify();
      if (!mounted || generation != _generation) { return; }
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TradeDocumentActorBoundary(child: Scaffold(
        appBar: AppBar(title: const Text('登録PNGの角印プレビュー')),
        body: PdfPreview.builder(pagesBuilder: (_, pages) => PdfPinchPages(pages: pages),
          build: (_) async => bytes, allowPrinting: true, allowSharing: true,
          canChangePageFormat: false, canChangeOrientation: false),
      ))));
      actorLease.verify();
      if (mounted && generation == _generation) { setState(() => _previewedHash = png.sha256); }
    } catch (_) {
      if (mounted && generation == _generation) { setState(() => _error = 'PNG角印をプレビューできませんでした。'); }
    } finally {
      actorLease.dispose();
      if (mounted && generation == _generation) { setState(() => _busy = false); }
    }
  }
  Future<void> _save(bool enabled) async {
    final settings = _settings;
    final png = _pending ?? settings?.png;
    if (_busy || settings == null || !settings.available || _source == null ||
        (enabled && (png == null || _previewedHash != png.sha256))) {
      return;
    }
    final generation = _generation;
    setState(() { _busy = true; _error = null; });
    try {
      if (enabled && _extendedCandidate && (_registeredHash != png?.sha256 || !await _canEdit())) {
        throw StateError('追加保存とプレビューを確認してください。');
      }
      final result = await _source.save(settings, png: enabled ? _pending : null, enabled: enabled);
      if (!mounted || generation != _generation) { return; }
      setState(() { _settings = result; _pending = null; _previewedHash = null; });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(enabled
        ? 'PNG角印を保存しました。新しく保存する帳票に反映します。' : '登録PNGの使用をOFFにしました。')));
    } catch (_) {
      if (mounted && generation == _generation) { setState(() => _error = 'PNG角印を保存できませんでした。再読み込みして確認してください。'); }
    } finally {
      if (mounted && generation == _generation) { setState(() => _busy = false); }
    }
  }
  @override Widget build(BuildContext context) {
    final png = _pending ?? _settings?.png;
    final available = _settings?.available == true;
    final canUse = !_extendedCandidate || _registeredHash == png?.sha256;
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
        if (_toolsAllowed) ...[
          Wrap(spacing: 8, children: [
            OutlinedButton.icon(onPressed: _busy || !available ? null : () => _import(SealImportKind.camera),
              icon: const Icon(Icons.camera_alt), label: const Text('撮影して切り抜く')),
            OutlinedButton(onPressed: _busy || !available ? null : () => _import(SealImportKind.gallery),
              child: const Text('写真から選ぶ')),
            OutlinedButton(onPressed: _busy || !available ? null : () => _import(SealImportKind.file),
              child: const Text('画像・PDFを切り抜く')),
          ]),
          const Text('画像化したPNGは追加保存してから、使う印影を選びます。以前の印影・確定帳票は変更しません。'),
          OutlinedButton(onPressed: _busy ? null : () => _loadHistory(), child: const Text('追加保存した角印を選ぶ')),
          if (_historyLoaded && !_busy && _history.isEmpty)
            const Text('追加保存した角印はありません。画像を追加保存すると、ここで選べます。'),
          for (final version in _history) ListTile(
            title: Text('角印 ${version.createdAt.toLocal().toString().split('.').first}'),
            subtitle: Text('${version.width}×${version.height}px・${version.sha256.substring(0, 8)}'),
            trailing: TextButton(onPressed: _busy ? null : () => _chooseVersion(version), child: const Text('選択'))),
          if (_moreHistory) TextButton(onPressed: _busy ? null : () => _loadHistory(older: true), child: const Text('以前の角印を表示')),
        ],
        const Text('1MB以下・32〜2048px・RGB/RGBAの静止画PNG。透過背景を推奨します。'),
        OutlinedButton(onPressed: _busy || png == null ? null : _preview,
          child: const Text('登録PNGをプレビュー')),
        if (_extendedCandidate && _registeredHash != png?.sha256) FilledButton(
          onPressed: _busy || !available || png == null || _previewedHash != png.sha256 ? null : _register,
          child: const Text('このPNGを追加保存（使用中の印影は変更しない）')),
        FilledButton(onPressed: _busy || !available || png == null || !canUse || _previewedHash != png.sha256
          ? null : () => _save(true), child: Text(_extendedCandidate ? 'この印影を使用' : 'このPNGを保存して使用')),
        if (_settings?.enabled == true) TextButton(onPressed: _busy ? null : () => _save(false),
          child: const Text('登録PNGの使用をOFF')),
        if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        if (_error != null) TextButton(onPressed: _busy ? null : _load, child: const Text('再読み込み')),
      ],
    )));
  }
}

