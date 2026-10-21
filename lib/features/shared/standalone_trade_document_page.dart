import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../data/supabase_backend.dart';
import '../invoices/invoice_order_acceptance_pdf.dart';
import '../payroll/payment_order_pdf.dart';
import 'company_seal_pdf.dart';
import 'standalone_trade_document.dart';
import 'standalone_trade_document_repository.dart';
import 'standalone_trade_document_print_scope.dart';

/// Registration-context, standalone PDF. No contract or financial save occurs.
class StandaloneTradeDocumentPage extends StatefulWidget {
  const StandaloneTradeDocumentPage({
    super.key,
    required this.tradeCompanyId,
    required this.acceptance,
  });
  final String tradeCompanyId;
  final bool acceptance;

  @override
  State<StandaloneTradeDocumentPage> createState() => _StandaloneState();
}

class _StandaloneState extends State<StandaloneTradeDocumentPage>
    with WidgetsBindingObserver {
  final _repository = StandaloneTradeDocumentRepository.maybeCreate();
  final _controllers = <String, TextEditingController>{};
  StreamSubscription<dynamic>? _auth;
  late final StandaloneTradeDocumentPrintScope _printScope;
  Map<String, dynamic>? _context;
  Uint8List? _bytes;
  String? _error;
  bool _loading = true, _busy = false, _revoked = false;
  int _generation = 0;
  String get _title => widget.acceptance ? '注文請書を作成' : '注文書を作成';

  @override
  void initState() {
    super.initState();
    _printScope = StandaloneTradeDocumentPrintScope(
      verifyScope: _verify,
      currentBytes: () => _bytes,
      currentTarget: () => '${widget.tradeCompanyId}:${widget.acceptance}',
      onRevoke: _invalidate,
    );
    WidgetsBinding.instance.addObserver(this);
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      _invalidate();
      return;
    }
    if (SupabaseBackend.isInitialized) {
      _auth = SupabaseBackend.client.auth.onAuthStateChange.listen(
        (_) {
          try {
            _verify();
          } catch (_) {
            _invalidate();
          }
        },
        onError: (Object _) => _invalidate(),
        onDone: _invalidate,
      );
    }
    _load();
  }

  @override
  void didUpdateWidget(covariant StandaloneTradeDocumentPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tradeCompanyId != widget.tradeCompanyId ||
        oldWidget.acceptance != widget.acceptance) {
      _invalidate();
    }
  }

  void _verify() {
    if (_revoked || _repository == null) {
      throw StateError('会社詳細から開き直してください。');
    }
    _repository.verify();
  }

  void _invalidate() {
    _repository?.invalidate();
    if (_revoked) {
      return;
    }
    _revoked = true;
    _printScope.invalidate();
    _generation++;
    _bytes = null;
    _context = null;
    for (final controller in _controllers.values) {
      controller.clear();
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _loading = false;
        _error = 'ログイン状態が変わりました。会社詳細から開き直してください。';
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    try {
      _printScope.visibilityChanged(switch (state) {
        AppLifecycleState.resumed => StandalonePrintVisibility.resumed,
        AppLifecycleState.inactive => StandalonePrintVisibility.inactive,
        AppLifecycleState.hidden => StandalonePrintVisibility.hidden,
        AppLifecycleState.paused => StandalonePrintVisibility.paused,
        AppLifecycleState.detached => StandalonePrintVisibility.detached,
      });
    } catch (_) {
      _invalidate();
    }
  }

  Future<void> _load() async {
    try {
      _verify();
      final value = await _repository!.load(
        tradeCompanyId: widget.tradeCompanyId,
        acceptance: widget.acceptance,
      );
      _verify();
      if (value['trade_company_id'] != widget.tradeCompanyId ||
          value['acceptance'] != widget.acceptance) {
        throw StateError('対象会社が変わりました。会社詳細から開き直してください。');
      }
      if (!mounted) {
        return;
      }
      final template = Map<String, dynamic>.from(value['template'] as Map);
      final initial = <String, String>{
        'work_name': template['work_name']?.toString() ?? '',
        'work_address': template['work_address']?.toString() ?? '',
        'issue_date': '',
        'order_date': '',
        if (!widget.acceptance) ...{
          'period_start': '',
          'period_end': '',
          'total_amount_yen': '',
          'tax_amount_yen': '',
        },
        'intro_text': template['intro_text']?.toString() ??
            '発注者（以下「甲」という）は、受注者（以下「乙」という）に対し、下記の通り工事を発注します。',
        'acceptance_text': template['acceptance_text']?.toString() ??
            '乙は、貴殿から受領した{order_date}付の注文書記載の条件通り、本工事を請け負うことを承諾いたします。',
        'payment_conditions': template['payment_conditions']?.toString() ??
            '工事完了確認後、乙の指定口座に振り込む。',
        'notes': template['notes']?.toString() ?? '',
      };
      for (final party in ['issuer', 'counterparty']) {
        final data = Map<String, dynamic>.from(value[party] as Map);
        for (final key in ['address', 'corporate_number', 'representative_name']) {
          initial['$party.$key'] = data[key]?.toString() ?? '';
        }
      }
      for (final entry in initial.entries) {
        _controllers[entry.key] = TextEditingController(text: entry.value);
      }
      setState(() {
        _context = value;
        _loading = false;
      });
    } catch (error) {
      if (mounted && !_revoked) {
        setState(() {
          _loading = false;
          _error = error is StateError
              ? error.message.toString()
              : '登録会社の情報を確認できません。会社詳細から開き直してください。';
        });
      }
    }
  }

  void _edited() {
    _generation++;
    if (_bytes != null || _error != null) {
      setState(() {
        _bytes = null;
        _error = null;
      });
    }
  }

  Future<void> _generate() async {
    final context = _context;
    if (_busy || context == null || _revoked) {
      return;
    }
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _bytes = null;
      _error = null;
    });
    try {
      _verify();
      final attachment = standaloneTradeDocument(
        context: context,
        fields: {
          for (final entry in _controllers.entries) entry.key: entry.value.text,
        },
      );
      final font = await CompanySealPdf.loadFont();
      _verify();
      final document = pw.Document(
        theme: pw.ThemeData.withFont(base: font, bold: font),
      );
      if (widget.acceptance) {
        await InvoiceOrderAcceptancePdf.append(
          document,
          attachment,
          regularFont: font,
          boldFont: font,
        );
      } else {
        await PaymentOrderPdf.append(
          document,
          attachment,
          regularFont: font,
          boldFont: font,
        );
      }
      _verify();
      final bytes = await document.save();
      _verify();
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() => _bytes = bytes);
    } catch (error) {
      if (mounted && !_revoked) {
        setState(() {
          _error = error is StateError
              ? error.message.toString()
              : '帳票を作成できません。入力内容を確認してください。';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _print() async {
    final bytes = _bytes;
    if (_busy || bytes == null || _revoked) {
      return;
    }
    setState(() => _busy = true);
    try {
      _verify();
      _printScope.begin(bytes);
      await Printing.layoutPdf(
        name: widget.acceptance ? '注文請書.pdf' : '注文書.pdf',
        format: PdfPageFormat.a4,
        onLayout: (_) async => _printScope.layout(),
      );
      _verify();
    } catch (_) {
      if (mounted && !_revoked) {
        setState(() => _error = '印刷を完了できません。状態を確認してください。');
      }
    } finally {
      _printScope.end();
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Widget _input(String key, String label, {int lines = 1, int max = 240,
    bool number = false, String? hint}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: _controllers[key],
      enabled: !_busy && !_revoked,
      maxLines: lines,
      maxLength: max,
      keyboardType: number ? TextInputType.number : null,
      onChanged: (_) => _edited(),
      decoration: InputDecoration(labelText: label, hintText: hint,
        border: const OutlineInputBorder()),
    ),
  );

  Widget _party(String key, String title) {
    final data = Map<String, dynamic>.from(_context![key] as Map);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      Text(data['name']?.toString() ?? ''),
      const SizedBox(height: 12),
      _input('$key.address', '住所（必須）', lines: 2),
      _input('$key.corporate_number', '法人番号（任意・13桁）', max: 13,
        number: true),
      _input('$key.representative_name', '代表者名（必須）', max: 80),
    ]);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _revoked = true;
    _printScope.invalidate();
    _repository?.invalidate();
    _auth?.cancel();
    _repository?.dispose();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: SafeArea(child: _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(padding: const EdgeInsets.all(16), children: [
          if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          if (!_revoked && _context != null) ...[
            const Text('工事名・工事場所・日付と、不足している住所・代表者名を入力してください。'),
            ExpansionTile(leading: const Icon(Icons.help_outline),
              title: const Text('作成について'),
              children: const [Padding(padding: EdgeInsets.all(12), child: Text(
                '登録会社名は変更できません。文面の初期値を必要に応じて編集し、帳票を確認してください。\n'
                'この画面では請求書・支払証明書・金融データを保存しません。\n'
                '自社で内容を確認する単体帳票です。相手会社の承認・印影はまだ付いていません。双方の承認済み共有帳票としては利用できません。\n'
                '注文書の請負代金・消費税額は実額を手入力してください。日付はYYYY-MM-DDで入力します。\n'
                '入力を変えた場合は帳票を作り直してください。画面を離れたり認証が変わった場合は会社詳細から開き直してください。'))]),
            const SizedBox(height: 12),
            _input('work_name', '工事名（必須）'),
            _input('work_address', '工事場所（必須）', lines: 2),
            _input('issue_date', widget.acceptance ? '承諾日（必須）' : '発行日（必須）',
              max: 10, hint: 'YYYY-MM-DD'),
            _input('order_date', '注文書日（必須）', max: 10, hint: 'YYYY-MM-DD'),
            if (!widget.acceptance) ...[
              _input('period_start', '工期の開始日（必須）', max: 10, hint: 'YYYY-MM-DD'),
              _input('period_end', '工期の終了日（必須）', max: 10, hint: 'YYYY-MM-DD'),
              _input('total_amount_yen', '請負代金（税込・必須）', max: 12, number: true),
              _input('tax_amount_yen', 'うち消費税額（必須）', max: 12, number: true),
            ],
            _party('issuer', widget.acceptance ? '乙・受注者（自社）' : '甲・発注者（自社）'),
            _party('counterparty', widget.acceptance ? '甲・発注者（登録会社）' : '乙・受注者（登録会社）'),
            ExpansionTile(title: const Text('文面を編集'), children: [
              if (widget.acceptance) _input('acceptance_text', '承諾文', lines: 4, max: 400)
              else _input('intro_text', '冒頭文', lines: 4, max: 400),
              _input('payment_conditions', '支払条件', lines: 3, max: 400),
              _input('notes', 'その他特記事項', lines: 4, max: 600),
            ]),
            const SizedBox(height: 12),
            FilledButton.icon(onPressed: _busy ? null : _generate,
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('帳票を確認')),
            if (_busy) const LinearProgressIndicator(),
            if (bytes != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(onPressed: _busy ? null : _print,
                icon: const Icon(Icons.print_outlined), label: const Text('印刷')),
              SizedBox(height: 520, child: PdfPreview(
                build: (_) async {
                  _verify();
                  if (!identical(bytes, _bytes)) {
                    throw StateError('入力内容が更新されました。帳票を作り直してください。');
                  }
                  return bytes;
                },
                initialPageFormat: PdfPageFormat.a4,
                canChangePageFormat: false,
                canChangeOrientation: false,
                allowPrinting: false,
                allowSharing: false,
              )),
            ],
          ],
        ])),
    );
  }
}
