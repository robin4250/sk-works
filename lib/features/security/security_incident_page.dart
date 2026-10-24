import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../international/language_controller.dart';
import '../shared/company_seal_pdf.dart';
import 'security_pdf_preview.dart';
import '../settings/master_protected_page.dart';
import 'security_export_guard.dart';
import 'security_actor_boundary.dart';
import 'security_incident.dart';
import 'security_incident_repository.dart';
import 'platform_monitor_page.dart';
import 'security_collector_page.dart';
import 'security_incident_report.dart';

import 'dart:convert';

class SecurityIncidentPage extends StatefulWidget {
  const SecurityIncidentPage({super.key, this.loadRecords, this.incidentId});
  final Future<List<SecurityIncident>> Function()? loadRecords;
  final String? incidentId;
  @override
  State<SecurityIncidentPage> createState() => _SecurityIncidentPageState();
}

class _SecurityIncidentPageState extends State<SecurityIncidentPage> {
  bool _loading = true, _failed = false;
  List<SecurityIncident> _records = const [];
  int _generation = 0;
  String? _recordActor;
  bool get _english => SkoLanguageController.isEnglish;
  String _text(String japanese, String english) =>
      _english ? english : japanese;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _failed = false;
      _records = const [];
    });
    try {
      final repository = SecurityIncidentRepository.maybeCreate();
      final actor = repository?.currentActor;
      final loader = widget.loadRecords ?? repository?.load;
      if (loader == null) {
        throw StateError('Unavailable');
      }
      final records = await loader();
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _records = records;
        _recordActor = actor;
        _loading = false;
      });
      final id = widget.incidentId;
      if (id != null) {
        final matches = records.where((record) => record.id == id);
        if (matches.length == 1) {
          await _open(matches.single);
        }
      }
    } catch (_) {
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  Future<void> _open(SecurityIncident record) => Navigator.of(context)
      .push<void>(
        MaterialPageRoute(
          builder: (_) => MasterProtectedPage(
            title: _text('記録の詳細', 'Record details'),
            child: SecurityActorBoundary(
              initialActor: _recordActor,
              child: SecurityIncidentDetailPage(record: record),
            ),
          ),
        ),
      );
  void _help() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(_text('セキュリティ記録について', 'About security records')),
      content: SingleChildScrollView(
        child: Text(
          _text(
            'マスター専用の記録です。検知は攻撃確定ではありません。調査区分と収集状態を分けて確認します。収集中・前後ログ不足の記録は完全な記録ではありません。PDFプレビューは2本指で拡大できます。印刷・保存・共有は同じ安全化済みの内容で、出力時に権限を再確認します。本文・個人情報・秘密情報は含めません。隔離環境の検証段階で、本番の自動遮断は行いません。',
            'Master-only records. Detection does not confirm an attack. Investigation and collection states are separate. Collecting or missing logs indicate incomplete records. Pinch the PDF preview with two fingers to zoom. Print, save and share recheck authorization and use the same sanitized report, without message bodies, personal information or secrets. This is an isolated validation stage, without automatic production blocking.',
          ),
        ),
      ),
      actions: [
        IconButton(
          tooltip: '収集されたアクセス記録',
          icon: const Icon(Icons.radar),
          onPressed: () => Navigator.of(context).push<void>(MaterialPageRoute(
            builder: (_) => const MasterProtectedPage(
              title: '収集されたアクセス記録',
              child: SecurityActorBoundary(child: SecurityCollectorPage()),
            ),
          )),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(_text('閉じる', 'Close')),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_text('セキュリティ記録', 'Security records')),
      actions: [
        IconButton(
          tooltip: 'プラットフォーム監視',
          icon: const Icon(Icons.monitor_heart_outlined),
          onPressed: () => Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => const MasterProtectedPage(
                title: 'プラットフォーム監視',
                child: SecurityActorBoundary(child: PlatformMonitorPage()),
              ),
            ),
          ),
        ),
        IconButton(
          onPressed: _help,
          icon: const Icon(Icons.help_outline),
          tooltip: _text('ヘルプ', 'Help'),
        ),
        IconButton(
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
          tooltip: _text('更新', 'Refresh'),
        ),
      ],
    ),
    body: SafeArea(
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _failed
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _text(
                      '記録を取得できません。未接続・権限・通信状態を確認してください。',
                      'Records unavailable. Check connection and access.',
                    ),
                  ),
                  TextButton(
                    onPressed: _load,
                    child: Text(_text('再読み込み', 'Retry')),
                  ),
                ],
              ),
            )
          : _records.isEmpty
          ? Center(child: Text(_text('保存された記録はありません。', 'No saved records.')))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _records.length,
              separatorBuilder: (_, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final record = _records[index];
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.policy_outlined),
                    title: Text(record.statusLabel(_english)),
                    subtitle: Text(
                      '${record.detectedAt.toLocal()}\n${record.collectionLabel(_english)} · ${record.events.length} ${_text('件', 'events')}',
                    ),
                    isThreeLine: true,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _open(record),
                  ),
                );
              },
            ),
    ),
  );
}

class SecurityIncidentDetailPage extends StatefulWidget {
  const SecurityIncidentDetailPage({super.key, required this.record});
  final SecurityIncident record;
  @override
  State<SecurityIncidentDetailPage> createState() =>
      _SecurityIncidentDetailPageState();
}

class _SecurityIncidentDetailPageState
    extends State<SecurityIncidentDetailPage> {
  bool _busy = false;
  late final _report = SecurityIncidentReportData(widget.record);
  final _repository = SecurityIncidentRepository.maybeCreate();
  late final String? _actor;
  @override
  void initState() {
    super.initState();
    _actor = _repository?.currentActor;
  }

  bool get _english => SkoLanguageController.isEnglish;
  String _text(String japanese, String english) =>
      _english ? english : japanese;

  Future<void> _beginExport(_SecurityExportKind kind) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => MasterProtectedPage(
          title: _text('セキュリティ記録の出力', 'Export security record'),
          child: SecurityActorBoundary(
            initialActor: _actor,
            child: _SecurityIncidentExportAction(
              report: _report,
              actor: _actor,
              kind: kind,
              english: _english,
            ),
          ),
        ),
      ),
    );
    if (mounted) {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_text('記録の詳細', 'Record details'))),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final line in _report.lines(_english))
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SelectableText(line),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _beginExport(_SecurityExportKind.preview),
                icon: const Icon(Icons.preview_outlined),
                label: Text(_text('PDFプレビュー', 'PDF preview')),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _beginExport(_SecurityExportKind.print),
                icon: const Icon(Icons.print_outlined),
                label: Text(_text('印刷', 'Print')),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _beginExport(_SecurityExportKind.pdf),
                icon: const Icon(Icons.save_alt),
                label: Text(_text('保存・共有', 'Save / share')),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _beginExport(_SecurityExportKind.json),
                icon: const Icon(Icons.data_object),
                label: Text(_text('JSON照合データ', 'JSON verification data')),
              ),
            ],
          ),
          Text(
            _text(
              'iPhoneでは共有メニューから「ファイルに保存」を選べます。',
              'On iPhone, choose Save to Files in the share menu.',
            ),
          ),
        ],
      ),
    ),
  );
}

class SecurityIncidentReport {
  static Future<Uint8List> build(
    SecurityIncidentReportData report, {
    required bool english,
    pw.Font? font,
  }) async {
    final regular = font ?? await CompanySealPdf.loadFont();
    final document = pw.Document(theme: pw.ThemeData.withFont(base: regular));
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        maxPages: 100,
        build: (_) => [
          for (final line in report.lines(english))
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 8),
              child: pw.Text(line, style: const pw.TextStyle(fontSize: 10)),
            ),
        ],
      ),
    );
    return document.save();
  }
}

enum _SecurityExportKind { preview, print, pdf, json }

/// Owns the handoff after the fresh MasterProtectedPage challenge. The source
/// detail may lock during Face ID without disposing this authenticated action.
class _SecurityIncidentExportAction extends StatefulWidget {
  const _SecurityIncidentExportAction({
    required this.report,
    required this.actor,
    required this.kind,
    required this.english,
  });
  final SecurityIncidentReportData report;
  final String? actor;
  final _SecurityExportKind kind;
  final bool english;

  @override
  State<_SecurityIncidentExportAction> createState() =>
      _SecurityIncidentExportActionState();
}

class _SecurityIncidentExportActionState
    extends State<_SecurityIncidentExportAction> {
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (widget.kind != _SecurityExportKind.preview) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _run());
    }
  }

  Future<void> _run() async {
    try {
      final repository = SecurityIncidentRepository.maybeCreate();
      if (repository == null) {
        throw StateError('Unavailable');
      }
      Future<void> authorize() => authorizeSecurityExport(
        actor: widget.actor,
        currentActor: () => repository.currentActor,
        isActive: () => mounted,
        // This widget exists only after the fresh master challenge succeeds.
        reauthenticate: () async => true,
        authorizeSnapshot: () =>
            repository.authorizeExport(widget.report, widget.actor),
      );
      await authorize();
      if (!mounted) {
        return;
      }
      final name = 'SKO-security-${widget.report.record.id}';
      if (widget.kind == _SecurityExportKind.json) {
        final box = context.findRenderObject() as RenderBox?;
        await SharePlus.instance.share(
          ShareParams(
            files: [
              XFile.fromData(
                Uint8List.fromList(utf8.encode(widget.report.json)),
                mimeType: 'application/json',
                name: '$name.json',
              ),
            ],
            fileNameOverrides: ['$name.json'],
            sharePositionOrigin: box == null
                ? null
                : box.localToGlobal(Offset.zero) & box.size,
          ),
        );
      } else {
        final bytes = await SecurityIncidentReport.build(
          widget.report,
          english: widget.english,
        );
        await authorize();
        if (!mounted) {
          return;
        }
        if (widget.kind == _SecurityExportKind.print) {
          await Printing.layoutPdf(
            name: '$name.pdf',
            onLayout: (_) async => bytes,
          );
        } else {
          await Printing.sharePdf(bytes: bytes, filename: '$name.pdf');
        }
      }
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _failed = true);
      }
    }
  }

  Future<void> _authorizePreview() async {
    final repository = SecurityIncidentRepository.maybeCreate();
    if (repository == null) throw StateError('Unavailable');
    await authorizeSecurityExport(
      actor: widget.actor,
      currentActor: () => repository.currentActor,
      isActive: () => mounted,
      reauthenticate: () async => true,
      authorizeSnapshot: () => repository.authorizeExport(widget.report, widget.actor),
    );
  }

  @override
  Widget build(BuildContext context) => widget.kind == _SecurityExportKind.preview
      ? SecurityPdfPreview(
          authorize: _authorizePreview,
          buildPdf: () => SecurityIncidentReport.build(widget.report, english: widget.english),
          printPdf: (bytes) async {
            await Printing.layoutPdf(name: 'SKO-security-${widget.report.record.id}.pdf', onLayout: (_) async => bytes);
          },
          sharePdf: (bytes) async {
            await Printing.sharePdf(bytes: bytes, filename: 'SKO-security-${widget.report.record.id}.pdf');
          },
          english: widget.english,
        )
      : Scaffold(
    appBar: AppBar(
      title: Text(widget.english ? 'Export security record' : 'セキュリティ記録の出力'),
    ),
    body: Center(
      child: _failed
          ? Text(widget.english ? 'Export failed.' : '出力できませんでした。')
          : const CircularProgressIndicator(),
    ),
  );
}


