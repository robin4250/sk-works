import '../../domain/company_seal_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../shared/company_seal_pdf.dart';
import 'company_seal_style_repository.dart';

import '../../international/language_controller.dart';
import '../people/company_submitted_document_repository.dart';

typedef CompanySealContext = ({String companyId, String name});

abstract class CompanySealSettingsDataSource {
  Future<CompanySealContext> loadContext();
  Future<bool> loadEnabled();
  Future<bool> saveEnabled(bool enabled);
  Future<CompanySealStyleSettings> loadStyle(CompanySealContext context);
  Future<void> saveStyle(CompanySealStyleSettings settings, String style);
}

class _RepositoryDataSource implements CompanySealSettingsDataSource {
  final _repository = CompanySubmittedDocumentRepository.maybeCreate();
  final _styles = CompanySealStyleRepository.maybeCreate();

  @override
  Future<CompanySealContext> loadContext() async => _styles!.loadContext();
  @override
  Future<bool> loadEnabled() async => _repository!.loadCompanySealEnabled();
  @override
  Future<bool> saveEnabled(bool enabled) async =>
      _repository!.saveCompanySealEnabled(enabled);
  @override
  Future<CompanySealStyleSettings> loadStyle(
    CompanySealContext context,
  ) async => _styles!.load(context);
  @override
  Future<void> saveStyle(
    CompanySealStyleSettings settings,
    String style,
  ) async => _styles!.save(settings, style);
}

class CompanySealSettingsPage extends StatefulWidget {
  const CompanySealSettingsPage({
    super.key,
    this.dataSource,
    this.loadCoverage,
  });

  final CompanySealSettingsDataSource? dataSource;
  final Future<String> Function(String name)? loadCoverage;

  @override
  State<CompanySealSettingsPage> createState() =>
      _CompanySealSettingsPageState();
}

class _CompanySealSettingsPageState extends State<CompanySealSettingsPage> {
  late final _source = widget.dataSource ?? _RepositoryDataSource();
  int _loadGeneration = 0;
  bool _loading = false;
  bool _coverageAvailable = false;
  CompanySealStyleSettings? _styleSettings;
  String _selectedStyle = CompanySealPdf.legacyStyle;
  String? _previewedStyle;
  String _missingCharacters = '';
  String? _styleError;
  ({String companyId, String name})? _companyContext;
  bool get _smallReisho =>
      _styleSettings != null &&
      CompanySealPdf.reishoGlyphSize(_styleSettings!.name, 32) < 4.5;
  bool? _enabled;
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    final generation = ++_loadGeneration;
    bool current() => mounted && generation == _loadGeneration;
    setState(() {
      _busy = true;
      _error = null;
      _styleError = null;
      _styleSettings = null;
      _previewedStyle = null;
      _coverageAvailable = false;
    });
    try {
      final companyContext = await _source.loadContext();
      final enabled = await _source.loadEnabled();
      CompanySealStyleSettings? settings;
      String? styleError;
      var missing = '';
      var coverageAvailable = false;
      try {
        settings = await _source.loadStyle(companyContext);
        try {
          missing =
              await (widget.loadCoverage ??
                  CompanySealPdf.unsupportedReishoCharacters)(settings.name);
          coverageAvailable = true;
        } catch (_) {
          // A Reisho asset failure must not remove the working legacy style.
          styleError = '会社角印の書体を読み込めませんでした。';
        }
      } catch (_) {
        styleError = '会社角印の書体を読み込めませんでした。';
      }
      // Validate the company even when style or coverage loading failed.
      final currentContext = await _source.loadContext();
      if (!current()) return;
      if (currentContext.companyId != companyContext.companyId) {
        setState(() {
          _enabled = null;
          _companyContext = null;
          _error = '会社の選択が変わりました。再読み込みしてください。';
        });
        return;
      }
      setState(() {
        _companyContext = companyContext;
        _enabled = enabled;
        _styleSettings = settings;
        _selectedStyle = settings?.style ?? CompanySealPdf.legacyStyle;
        _missingCharacters = missing;
        _coverageAvailable = coverageAvailable;
        _styleError = styleError;
      });
    } catch (_) {
      if (!current()) return;
      setState(() {
        _error = '会社角印の設定を読み込めませんでした。';
        _enabled = null;
        _companyContext = null;
        _styleSettings = null;
      });
    } finally {
      if (current()) {
        setState(() {
          _busy = false;
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _loadGeneration++;
    super.dispose();
  }

  Future<void> _save(bool enabled) async {
    if (_busy || _enabled == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final currentContext = await _source.loadContext();
      if (_companyContext?.companyId != currentContext.companyId) {
        throw StateError('Company context changed.');
      }
      final saved = await _source.saveEnabled(enabled);
      if (!mounted) return;
      setState(() {
        _enabled = saved;
        _busy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(SkoLanguageController.tr('会社角印の設定を保存しました'))),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = '会社角印の設定を保存できませんでした。';
        _busy = false;
      });
    }
  }

  Future<void> _preview() async {
    final settings = _styleSettings;
    if (_busy || settings == null) return;
    setState(() => _busy = true);
    try {
      if (_selectedStyle == CompanySealPdf.reishoStyle &&
          (!_coverageAvailable || _missingCharacters.isNotEmpty)) {
        throw StateError('Unsupported registered characters.');
      }
      final style = _selectedStyle;
      final font = await CompanySealPdf.loadStyleFont(style);
      final document = pw.Document();
      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (_) => pw.Column(
            children: [
              pw.Text(
                settings.name,
                style: pw.TextStyle(font: font, fontSize: 14),
              ),
              pw.SizedBox(height: 24),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  for (final size in [32.0, 42.0, 55.0])
                    pw.Column(
                      children: [
                        pw.Text('${size.toInt()} pt'),
                        pw.SizedBox(height: 8),
                        CompanySealPdf.build(
                          settings.name,
                          size: size,
                          font: font,
                          style: style,
                          companyId: settings.companyId,
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      );
      final bytes = await document.save();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(title: Text(SkoLanguageController.tr('角印プレビュー'))),
            body: PdfPreview(
              build: (_) async => bytes,
              canChangePageFormat: false,
              canChangeOrientation: false,
            ),
          ),
        ),
      );
      if (!mounted) return;
      setState(() => _previewedStyle = style);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = '角印プレビューを生成できませんでした。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveStyle() async {
    final settings = _styleSettings;
    if (_busy ||
        settings == null ||
        !settings.available ||
        _previewedStyle != _selectedStyle ||
        (_selectedStyle == CompanySealPdf.reishoStyle &&
            (!_coverageAvailable ||
                _missingCharacters.isNotEmpty ||
                _smallReisho))) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _source.saveStyle(settings, _selectedStyle);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(SkoLanguageController.tr('会社角印の印影を保存しました'))),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '会社角印の書体を保存できませんでした。';
      });
    }
  }

  Future<void> _showUsage() async {
    try {
      final usage = await rootBundle.loadString(
        'assets/fonts/company-seal/aoyagi-reisho/FONT-USAGE-utf8.txt',
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(SkoLanguageController.tr('隷書の利用条件')),
          content: SingleChildScrollView(child: SelectableText(usage)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(SkoLanguageController.tr('閉じる')),
            ),
          ],
        ),
      );
    } catch (_) {
      if (mounted) setState(() => _styleError = '隷書の説明を読み込めませんでした。');
    }
  }

  Future<void> _showExplanation() async {
    try {
      final data = await rootBundle.load(
        'assets/fonts/company-seal/aoyagi-reisho/FONT-EXPLANATION-original.pdf',
      );
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(
              title: Text(SkoLanguageController.tr('書体の解説（作者原文）')),
            ),
            body: PdfPreview(
              build: (_) async => bytes,
              canChangePageFormat: false,
              canChangeOrientation: false,
            ),
          ),
        ),
      );
    } catch (_) {
      if (mounted) setState(() => _styleError = '隷書の説明を読み込めませんでした。');
    }
  }

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(SkoLanguageController.tr('会社角印')),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text(SkoLanguageController.tr('会社角印')),
                content: Text(
                  SkoLanguageController.tr(
                    '会社専用のPNG印影は背景を透過して帳票に重ねます。新しく保存する帳票に反映し、過去の帳票は変更しません。会社名を自動で書き換える機能ではありません。隷書は無償社内試験用です。PDFで確認してから保存してください。',
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(SkoLanguageController.tr('閉じる')),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(SkoLanguageController.tr('会社共通。請求書・給与明細・支払証明書に反映します。')),
          const SizedBox(height: 12),
          if (_busy) const LinearProgressIndicator(),
          if (_enabled != null)
            SwitchListTile(
              title: Text(SkoLanguageController.tr('会社角印を表示')),
              value: _enabled!,
              onChanged: _busy ? null : _save,
            ),
          Text(SkoLanguageController.tr('OFFでも確認印・承認印と承認履歴は残ります。')),
          if (_styleSettings != null) ...[
            const SizedBox(height: 20),
            Text(_styleSettings!.name),
            Text(
              SkoLanguageController.tr(
                _styleSettings!.documentSnapshotsAvailable
                    ? '選んだ印影は新しく保存する帳票に反映します。過去の帳票は変更しません。'
                    : '書体選択は試験用です。現在の帳票の印影は変更しません。',
              ),
            ),
            DropdownButtonFormField<String>(
              key: ValueKey(
                '${_styleSettings!.companyId}:${_styleSettings!.style}',
              ),
              initialValue: _selectedStyle,
              decoration: InputDecoration(
                labelText: SkoLanguageController.tr('会社角印のデザイン'),
              ),
              items: [
                for (final style in _styleSettings!.pngStyles)
                  DropdownMenuItem(
                    value: style,
                    child: Text(CompanySealDesign.designs[style]!.label),
                  ),
                DropdownMenuItem(
                  value: CompanySealPdf.legacyStyle,
                  child: Text(SkoLanguageController.tr('既存の角印')),
                ),
                DropdownMenuItem(
                  value: CompanySealPdf.reishoStyle,
                  child: Text(SkoLanguageController.tr('隷書（無償社内試験）')),
                ),
              ],
              onChanged: _busy
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() {
                          _selectedStyle = value;
                          _previewedStyle = null;
                        });
                      }
                    },
            ),
            if (CompanySealDesign.isPng(_selectedStyle)) ...[
              const SizedBox(height: 12),
              Center(
                child: Image.asset(
                  CompanySealDesign.designs[_selectedStyle]!.asset,
                  width: 150,
                  height: 150,
                  fit: BoxFit.contain,
                  semanticLabel: '${_styleSettings!.name}の角印',
                ),
              ),
              Text(SkoLanguageController.tr('この会社専用の印影です。別の会社名には自動変換されません。')),
            ],
            if (!_styleSettings!.available)
              Text(SkoLanguageController.tr('書体の保存準備中です。PDFプレビューのみ利用できます。')),
            if (_selectedStyle == CompanySealPdf.reishoStyle) ...[
              Text(
                SkoLanguageController.tr('作者の利用条件を確認してください。有料配布への対応は未確定です。'),
              ),
              if (_missingCharacters.isNotEmpty)
                Text(
                  '${SkoLanguageController.tr('未対応文字')}: $_missingCharacters',
                ),
              if (_smallReisho)
                Text(
                  SkoLanguageController.tr(
                    '登録会社名が長く、小さい帳票の印影を読み取れません。隷書はまだ保存できません。',
                  ),
                ),
            ],
            OutlinedButton(
              onPressed:
                  _busy ||
                      (_selectedStyle == CompanySealPdf.reishoStyle &&
                          !_coverageAvailable)
                  ? null
                  : _preview,
              child: Text(SkoLanguageController.tr('角印プレビュー')),
            ),
            FilledButton(
              onPressed:
                  _busy ||
                      !_styleSettings!.available ||
                      _previewedStyle != _selectedStyle ||
                      (_selectedStyle == CompanySealPdf.reishoStyle &&
                          (!_coverageAvailable ||
                              _missingCharacters.isNotEmpty ||
                              _smallReisho))
                  ? null
                  : _saveStyle,
              child: Text(SkoLanguageController.tr('印影を保存')),
            ),
            TextButton(
              onPressed: _showUsage,
              child: Text(SkoLanguageController.tr('隷書の利用条件')),
            ),
            TextButton(
              onPressed: _showExplanation,
              child: Text(SkoLanguageController.tr('書体の解説（作者原文）')),
            ),
          ],
          if (_styleError != null) ...[
            Text(SkoLanguageController.tr(_styleError!)),
            TextButton(
              onPressed: _busy ? null : _load,
              child: Text(SkoLanguageController.tr('再読み込み')),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              SkoLanguageController.tr(_error!),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            TextButton(
              onPressed: _busy ? null : _load,
              child: Text(SkoLanguageController.tr('再読み込み')),
            ),
          ],
        ],
      ),
    );
  }
}
