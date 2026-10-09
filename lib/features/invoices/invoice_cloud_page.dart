import 'package:flutter/material.dart';

import '../../domain/invoice_engine.dart';
import '../../international/language_controller.dart';
import '../notifications/notification_bell.dart';
import 'invoice_cloud_repository.dart';
import 'invoice_approval_repository.dart';
import 'invoice_stamp_surname_dialog.dart';
import 'invoice_pdf_service.dart';
import 'invoice_settings_page.dart';

enum _InvoiceBrowseMode { all, company }
enum _InvoicePeriodMode { month, year }

class InvoiceCloudPage extends StatefulWidget {
  const InvoiceCloudPage({
    super.key,
    this.initialInvoiceId,
  });

  final String? initialInvoiceId;

  @override
  State<InvoiceCloudPage> createState() => _InvoiceCloudPageState();
}

class _InvoiceCloudPageState extends State<InvoiceCloudPage> {
  final _repository = InvoiceCloudRepository.maybeCreate();
  final _invoices = <InvoiceCalculationResult>[];

  bool _loading = true;
  bool _canManageSettings = false;
  String? _error;
  _InvoiceBrowseMode _browseMode = _InvoiceBrowseMode.all;
  _InvoicePeriodMode _periodMode = _InvoicePeriodMode.month;
  DateTime _period = DateTime(DateTime.now().year, DateTime.now().month);
  String? _companyFilter;
  bool _openedInitialInvoice = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repository = _repository;
    if (repository == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = SkoLanguageController.isEnglish ? 'Invoices are unavailable.' : '請求書を利用できません。';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final values = await Future.wait([
        repository.loadAll(),
        repository.canManageFinancials(),
      ]);
      final rows = values[0] as List<InvoiceCalculationResult>;
      final canManage = values[1] as bool;
      if (!mounted) return;
      setState(() {
        _invoices
          ..clear()
          ..addAll(rows);
        _canManageSettings = canManage;
        _loading = false;
        if (_companyFilter != null &&
            !_companies.contains(_companyFilter)) {
          _companyFilter = null;
        }

        final hasCurrentPeriod = _invoices.any((invoice) {
          final month = _invoiceMonth(invoice);
          return month != null &&
              month.year == _period.year &&
              month.month == _period.month;
        });
        if (!hasCurrentPeriod && _invoices.isNotEmpty) {
          final months = _invoices
              .map(_invoiceMonth)
              .whereType<DateTime>()
              .toList()
            ..sort((a, b) => b.compareTo(a));
          if (months.isNotEmpty) {
            _period = DateTime(months.first.year, months.first.month);
          }
        }
      });

      if (!_openedInitialInvoice &&
          (widget.initialInvoiceId ?? '').isNotEmpty) {
        _openedInitialInvoice = true;
        final target = _invoices.where(
          (invoice) => invoice.invoiceId == widget.initialInvoiceId,
        );
        if (target.isNotEmpty && mounted) {
          await _openPreview(target.first);
        }
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  List<String> get _companies {
    final values = _invoices
        .map((invoice) => invoice.customerId.trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return values;
  }

  DateTime? _invoiceMonth(InvoiceCalculationResult invoice) {
    final text = invoice.billingPeriod
        .replaceAll('年', '/')
        .replaceAll('月', '')
        .replaceAll('-', '/');
    final parts = text.split('/').where((part) => part.trim().isNotEmpty).toList();
    if (parts.length < 2) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    if (year == null || month == null || month < 1 || month > 12) {
      return null;
    }
    return DateTime(year, month);
  }

  List<InvoiceCalculationResult> get _visibleInvoices {
    final result = _invoices.where((invoice) {
      final month = _invoiceMonth(invoice);
      if (month == null) return false;

      final periodMatches = _periodMode == _InvoicePeriodMode.month
          ? month.year == _period.year && month.month == _period.month
          : month.year == _period.year;

      if (!periodMatches) return false;

      if (_browseMode == _InvoiceBrowseMode.company &&
          _companyFilter != null &&
          invoice.customerId != _companyFilter) {
        return false;
      }

      return true;
    }).toList();

    result.sort((a, b) {
      final am = _invoiceMonth(a) ?? DateTime(1970);
      final bm = _invoiceMonth(b) ?? DateTime(1970);
      final byMonth = bm.compareTo(am);
      if (byMonth != 0) return byMonth;
      return a.customerId.compareTo(b.customerId);
    });
    return result;
  }

  void _movePeriod(int delta) {
    setState(() {
      if (_periodMode == _InvoicePeriodMode.month) {
        _period = DateTime(_period.year, _period.month + delta);
      } else {
        _period = DateTime(_period.year + delta, 1);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleInvoices;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          SkoLanguageController.isEnglish ? 'Invoices' : '請求書',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          const SkoNotificationBell(),
          if (_canManageSettings)
            IconButton(
              tooltip: SkoLanguageController.isEnglish ? 'Invoice Settings' : '請求書設定',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const InvoiceSettingsPage(),
                ),
              ),
              icon: const Icon(Icons.settings_outlined),
            ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _ErrorState(message: _error!, onRetry: _load)
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                        child: SegmentedButton<_InvoiceBrowseMode>(
                          segments: [
                            ButtonSegment(
                              value: _InvoiceBrowseMode.all,
                              label: Text(SkoLanguageController.isEnglish ? 'All' : '一覧'),
                              icon: Icon(Icons.list_alt_outlined),
                            ),
                            ButtonSegment(
                              value: _InvoiceBrowseMode.company,
                              label: Text(SkoLanguageController.isEnglish ? 'By Company' : '会社別'),
                              icon: Icon(Icons.business_outlined),
                            ),
                          ],
                          selected: {_browseMode},
                          onSelectionChanged: (value) {
                            setState(() => _browseMode = value.first);
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
                        child: SegmentedButton<_InvoicePeriodMode>(
                          segments: [
                            ButtonSegment(
                              value: _InvoicePeriodMode.month,
                              label: Text(SkoLanguageController.isEnglish ? 'Month' : '月'),
                            ),
                            ButtonSegment(
                              value: _InvoicePeriodMode.year,
                              label: Text(SkoLanguageController.isEnglish ? 'Year' : '年'),
                            ),
                          ],
                          selected: {_periodMode},
                          onSelectionChanged: (value) {
                            setState(() {
                              _periodMode = value.first;
                              _period = DateTime(_period.year, _period.month);
                            });
                          },
                        ),
                      ),
                      if (_browseMode == _InvoiceBrowseMode.company)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
                          child: DropdownButtonFormField<String?>(
                            initialValue: _companyFilter,
                            decoration: InputDecoration(
                              labelText: SkoLanguageController.isEnglish ? 'Select Company' : '取引会社を選択',
                              prefixIcon: Icon(Icons.business_center_outlined),
                            ),
                            items: [
                              DropdownMenuItem<String?>(
                                value: null,
                                child: Text(SkoLanguageController.isEnglish ? 'All Companies' : 'すべての会社'),
                              ),
                              for (final company in _companies)
                                DropdownMenuItem<String?>(
                                  value: company,
                                  child: Text(company),
                                ),
                            ],
                            onChanged: (value) =>
                                setState(() => _companyFilter = value),
                          ),
                        ),
                      _PeriodHeader(
                        label: _periodMode == _InvoicePeriodMode.month
                            ? (SkoLanguageController.isEnglish ? '${_period.month}/${_period.year}' : '${_period.year}年${_period.month}月')
                            : (SkoLanguageController.isEnglish ? '${_period.year}' : '${_period.year}年'),
                        onPrevious: () => _movePeriod(-1),
                        onNext: () => _movePeriod(1),
                      ),
                      if (_periodMode == _InvoicePeriodMode.year &&
                          visible.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      SkoLanguageController.isEnglish ? 'Year total: ${visible.length} invoices / ${_yen(visible.fold<int>(0, (sum, invoice) => sum + invoice.grandTotalYen))}' : '年間 ${visible.length}件 / 合計 ${_yen(visible.fold<int>(0, (sum, invoice) => sum + invoice.grandTotalYen))}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  PopupMenuButton<String>(
                                    tooltip: SkoLanguageController.isEnglish ? 'Annual Output' : '年間出力',
                                    onSelected: (value) =>
                                        _annualAction(value, visible),
                                    itemBuilder: (_) => [
                                      PopupMenuItem(
                                        value: 'preview',
                                        child: Text(SkoLanguageController.isEnglish ? 'Annual Preview' : '年間プレビュー'),
                                      ),
                                      PopupMenuItem(
                                        value: 'print',
                                        child: Text(SkoLanguageController.isEnglish ? 'Annual Print' : '年間印刷'),
                                      ),
                                      PopupMenuItem(
                                        value: 'save',
                                        child: Text(SkoLanguageController.isEnglish ? 'Annual Save' : '年間保存'),
                                      ),
                                      PopupMenuItem(
                                        value: 'mail',
                                        child: Text(SkoLanguageController.isEnglish ? 'Annual Email' : '年間メール送信'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      Expanded(
                        child: visible.isEmpty
                            ? Center(
                                child: Text(
                                  SkoLanguageController.isEnglish ? 'No invoices for this period.' : 'この期間の請求書はありません',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              )
                            : RefreshIndicator(
                                onRefresh: _load,
                                child: ListView.separated(
                                  padding:
                                      const EdgeInsets.fromLTRB(12, 4, 12, 24),
                                  itemCount: visible.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 9),
                                  itemBuilder: (context, index) {
                                    final invoice = visible[index];
                                    final month = _invoiceMonth(invoice);
                                    return Card(
                                      child: InkWell(
                                        borderRadius:
                                            BorderRadius.circular(20),
                                        onTap: () =>
                                            _openPreview(invoice),
                                        child: Padding(
                                          padding: const EdgeInsets.all(16),
                                          child: Row(
                                            children: [
                                              const CircleAvatar(
                                                child: Icon(
                                                  Icons.receipt_long_outlined,
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      invoice.customerId,
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w900,
                                                        fontSize: 16,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 3),
                                                    Text(
                                                      month == null
                                                          ? invoice
                                                              .billingPeriod
                                                          : (SkoLanguageController.isEnglish ? '${month.month}/${month.year}' : '${month.year}年${month.month}月'),
                                                    ),
                                                    const SizedBox(height: 5),
                                                    Text(
                                                      SkoLanguageController.isEnglish ? '${invoice.siteCalculations.length} sites' : '${invoice.siteCalculations.length}現場',
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .bodySmall,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              Text(
                                                _yen(invoice.grandTotalYen),
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w900,
                                                    ),
                                              ),
                                              const SizedBox(width: 4),
                                              const Icon(Icons.chevron_right),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                      ),
                    ],
                  ),
      ),
    );
  }

  Future<void> _openPreview(InvoiceCalculationResult invoice) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => InvoicePreviewPage(invoice: invoice),
      ),
    );
  }

  Future<void> _annualAction(
    String action,
    List<InvoiceCalculationResult> invoices,
  ) async {
    if (invoices.isEmpty) return;
    final title = SkoLanguageController.isEnglish ? '${_period.year} Invoices' : '${_period.year}年 請求書';

    try {
      switch (action) {
        case 'print':
          await InvoicePdfService.printInvoices(invoices, title: title);
          break;
        case 'save':
          await InvoicePdfService.shareInvoices(
            invoices,
            title: title,
            subject: title,
            body: SkoLanguageController.isEnglish ? 'Choose Save to Files from the share menu.' : '共有メニューから「ファイルに保存」を選択してください。',
          );
          break;
        case 'mail':
          await InvoicePdfService.shareInvoices(
            invoices,
            title: title,
            subject: title,
            body: SkoLanguageController.isEnglish ? 'Annual invoice PDF attached.' : '年間請求書PDFを送付します。',
          );
          break;
        default:
          if (!mounted) return;
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => InvoicePdfPreviewPage(
                invoices: invoices,
                title: title,
              ),
            ),
          );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${SkoLanguageController.isEnglish ? 'Could not output invoice PDF' : '請求書PDFを出力できませんでした'}: $error')),
      );
    }
  }
}

class _PeriodHeader extends StatelessWidget {
  const _PeriodHeader({
    required this.label,
    required this.onPrevious,
    required this.onNext,
  });

  final String label;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
      child: Row(
        children: [
          IconButton(
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ),
          IconButton(
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

class InvoicePreviewPage extends StatefulWidget {
  const InvoicePreviewPage({super.key, required this.invoice});
  final InvoiceCalculationResult invoice;

  @override
  State<InvoicePreviewPage> createState() => _InvoicePreviewPageState();
}

class _InvoicePreviewPageState extends State<InvoicePreviewPage> {
  final _approvals = InvoiceApprovalRepository.maybeCreate();
  int _revision = 0;
  bool _busy = false;

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('承認情報を更新できませんでした。帳票機能の更新状況と権限を確認してください。\n$error')),
    );
  }

  Future<void> _manageApprovals() async {
    final repository = _approvals;
    if (repository == null || _busy) return;
    setState(() => _busy = true);
    try {
      final rows = await repository.loadForInvoice(widget.invoice.invoiceId);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (sheetContext) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '確認・承認と印影',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(SkoLanguageController.isEnglish
                    ? 'Explicit surnames are fixed when approved. Previous seals and approval history remain unchanged. Unconfigured seals keep their existing display.'
                    : '名字は本人が入力し、承認時に固定します。過去の印影と承認履歴は変更しません。未設定の印影は従来の表示を保持します。'),
                for (final row in rows)
                  ListTile(
                    title: Text(
                      '${row.name}：${row.approved ? '承認済み' : '承認待ち'}',
                    ),
                    subtitle: Text(
                      row.approved
                          ? '印影日付：${_displayDate(row.stampDisplayDate)}'
                          : '未承認の印影は表示されません',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (row.canCurrentUserSetStampSurname)
                          IconButton(
                            tooltip: SkoLanguageController.isEnglish ? 'Approval-seal surname' : '承認印の名字',
                            icon: const Icon(Icons.badge_outlined),
                            onPressed: () async {
                              Navigator.pop(sheetContext);
                              final saved = await editInvoiceStampSurname(
                                context, repository, widget.invoice.invoiceId,
                                initialSurname: row.draftStampSurname,
                              );
                              if (saved && mounted) setState(() => _revision++);
                            },
                          ),
                        if (row.canCurrentUserEditDisplayDate)
                          IconButton(
                            tooltip: '印影の表示日付',
                            icon: const Icon(Icons.edit_calendar_outlined),
                            onPressed: () async {
                              Navigator.pop(sheetContext);
                              await _editDisplayDate(row);
                            },
                          ),
                        if (row.canCurrentUserCancel)
                          TextButton(
                            onPressed: () async {
                              Navigator.pop(sheetContext);
                              try {
                                await repository.cancel(
                                  widget.invoice.invoiceId,
                                );
                                if (mounted) setState(() => _revision++);
                              } catch (error) {
                                _showError(error);
                              }
                            },
                            child: const Text('承認取消'),
                          ),
                      ],
                    ),
                  ),
                TextButton.icon(
                  icon: const Icon(Icons.history),
                  label: const Text('実際の承認履歴'),
                  onPressed: () async {
                    Navigator.pop(sheetContext);
                    await _showHistory();
                  },
                ),
              ],
            ),
          ),
        ),
      );
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editDisplayDate(InvoiceApprovalRecord row) async {
    final mode = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('印影の表示日付'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'select'),
            child: const Text('日付を指定'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'reset'),
            child: const Text('会社設定に戻す'),
          ),
        ],
      ),
    );
    if (mode == null || !mounted) return;
    DateTime? date;
    if (mode == 'select') {
      final initial =
          row.displayDateOverride ?? row.stampDisplayDate ?? DateTime.now();
      date = await showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: DateTime(1900),
        lastDate: DateTime(2200),
      );
      if (date == null || !mounted) return;
    }
    try {
      await _approvals!.setDisplayDate(
        widget.invoice.invoiceId,
        row.userId,
        date,
      );
      if (mounted) setState(() => _revision++);
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _showHistory() async {
    try {
      final history = await _approvals!.loadHistory(widget.invoice.invoiceId);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('実際の承認履歴'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (history.isEmpty) const Text('承認履歴はありません'),
                  for (final entry in history)
                    ListTile(
                      title: Text(
                        '${entry.actorName}：${_actionLabel(entry.action)}',
                      ),
                      subtitle: Text(_actualTimestamp(entry.createdAt)),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('閉じる'),
            ),
          ],
        ),
      );
    } catch (error) {
      _showError(error);
    }
  }

  static String _actionLabel(String action) => switch (action) {
    'approved' => '承認',
    'cancelled' => '承認取消',
    'invalidated' => '内容変更による再承認',
    'display_date_changed' => '印影表示日付の変更',
    _ => action,
  };

  static String _displayDate(DateTime? date) =>
      date == null ? '日付なし' : '${date.year}/${date.month}/${date.day}';

  static String _actualTimestamp(DateTime? timestamp) {
    if (timestamp == null) return '日時未記録';
    final japan = timestamp.toUtc().add(const Duration(hours: 9));
    return '${japan.year}/${japan.month}/${japan.day} '
        '${japan.hour.toString().padLeft(2, '0')}:${japan.minute.toString().padLeft(2, '0')}:${japan.second.toString().padLeft(2, '0')}（日本時間）';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: InvoicePdfPreviewPage(
      key: ValueKey(_revision),
      invoices: [widget.invoice],
      title: SkoLanguageController.isEnglish ? 'Invoice Preview' : '請求書プレビュー',
    ),
    bottomNavigationBar: _approvals == null || widget.invoice.invoiceId.isEmpty
        ? null
        : SafeArea(
            child: TextButton.icon(
              onPressed: _busy ? null : _manageApprovals,
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('承認履歴・印影設定'),
            ),
          ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 42),
            const SizedBox(height: 12),
            Text(
              SkoLanguageController.isEnglish ? 'Could not load invoices' : '請求書を読み込めませんでした',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(SkoLanguageController.isEnglish ? 'Retry' : '再試行'),
            ),
          ],
        ),
      ),
    );
  }
}

String _yen(int value) {
  final negative = value < 0;
  final digits = value.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return '${negative ? '-' : ''}¥$buffer';
}
