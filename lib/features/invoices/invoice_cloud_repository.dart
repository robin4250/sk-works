import '../../domain/invoice_document_seal.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';
import '../../domain/invoice_engine.dart';

class InvoiceCloudRepository {
  InvoiceCloudRepository._(this._client);

  final SupabaseClient _client;

  static InvoiceCloudRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    return InvoiceCloudRepository._(client);
  }

  Future<({String companyId, String role})> membership() async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('SKOへのログインが必要です。');
    final rows = await _client
        .from('company_members')
        .select('company_id, role')
        .eq('user_id', user.id)
        .limit(1);
    if (rows.isEmpty) throw StateError('会社情報が見つかりません。');
    return (
      companyId: rows.first['company_id'] as String,
      role: rows.first['role']?.toString() ?? 'viewer',
    );
  }

  Future<bool> canManageFinancials() async {
    await membership();
    final value = await _client.rpc('current_feature_permissions');
    if (value is! Map) return false;
    final permissions = Map<String, dynamic>.from(value);
    return permissions['can_manage_invoices'] == true;
  }

  Future<String> _companyId() async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('SKOへのログインが必要です.');
    final rows = await _client
        .from('company_members')
        .select('company_id')
        .eq('user_id', user.id)
        .limit(1);
    if (rows.isEmpty) throw StateError('会社情報が見つかりません。');
    return rows.first['company_id'] as String;
  }

  static Map<String, String> registeredCustomerContact(
    Map<String, dynamic> registered, {
    Map<String, dynamic> fallback = const {},
  }) => {
    for (final key in const ['name', 'postal_code', 'address', 'phone'])
      key: (registered[key]?.toString().trim() ?? '').isNotEmpty
          ? registered[key].toString().trim()
          : fallback[key]?.toString().trim() ?? '',
  };

  Future<List<InvoiceCalculationResult>> loadAll() async {
    final companyId = await _companyId();
    // Keep the primary invoice query independent from related tables. An
    // unavailable customer/site relation must never hide an otherwise valid
    // saved invoice.
    Future<List<Map<String, dynamic>>> readRows(bool lifecycleReady) async =>
        await _client
            .from('invoices')
            .select(
              'id, customer_id, billing_period_start, billing_period_end, '
              'invoice_number, issue_date, detail_mode, subtotal, tax, '
              'grand_total, snapshot, updated_at, status, finalized_at, approval_finalized_at'
              '${lifecycleReady ? ', invoice_seal_frozen' : ''}',
            )
            .eq('company_id', companyId)
            .order('billing_period_start', ascending: false)
            .order('created_at', ascending: false);
    List<Map<String, dynamic>> invoices;
    try {
      invoices = await readRows(true);
    } on PostgrestException catch (error) {
      if (!['42703', 'PGRST204'].contains(error.code) ||
          !error.message.contains('invoice_seal_frozen'))
        rethrow;
      // Until invoice lifecycle migration is deployed, preserve all saved seals.
      invoices = await readRows(false);
    }

    Map<String, dynamic>? currentSealCompany;
    if (invoices.any(invoiceUsesCurrentSeal)) {
      final company = await _client
          .from('companies')
          .select('id,name,company_seal_style')
          .eq('id', companyId)
          .single();
      currentSealCompany = Map<String, dynamic>.from(company);
    }

    // Existing read-only RPC is company/admin scoped; never run directory sync
    // while opening reports. Missing optional access leaves snapshots available.
    final registeredContacts = <String, Map<String, dynamic>>{};
    try {
      final rawContacts = await _client.rpc('trade_company_workspace');
      if (rawContacts is List) {
        final ambiguous = <String>{};
        for (final rawContact in rawContacts) {
          if (rawContact is! Map) continue;
          final contact = Map<String, dynamic>.from(rawContact);
          final linkedCustomer = contact['customer_id']?.toString() ?? '';
          if (linkedCustomer.isEmpty) continue;
          if (registeredContacts.containsKey(linkedCustomer)) {
            ambiguous.add(linkedCustomer);
          }
          registeredContacts[linkedCustomer] = contact;
        }
        for (final id in ambiguous) {
          registeredContacts.remove(id);
        }
      }
    } catch (_) {
      // Retain snapshot/customer fallback for viewers without directory access.
    }
    final results = <InvoiceCalculationResult>[];
    for (final invoice in invoices) {
      try {
        final invoiceId = invoice['id']?.toString() ?? '';
        if (invoiceId.isEmpty) continue;

        final snapshot = invoice['snapshot'];
        final snapshotMap = snapshot is Map
            ? Map<String, dynamic>.from(snapshot)
            : const <String, dynamic>{};

        // Snapshot data is the durable fallback when the current registered
        // directory or related customer is unavailable. Optional lookup/RLS
        // changes must never make the saved invoice list disappear.
        var customerName =
            snapshotMap['customer_name']?.toString().trim() ?? '';
        var customerPostalCode =
            snapshotMap['customer_postal_code']?.toString().trim() ?? '';
        var customerAddress =
            snapshotMap['customer_address']?.toString().trim() ?? '';
        var customerPhone =
            snapshotMap['customer_phone']?.toString().trim() ?? '';
        final registered =
            registeredContacts[invoice['customer_id']?.toString() ?? ''];
        if (registered != null) {
          final contact = registeredCustomerContact(
            registered,
            fallback: {
              'name': customerName,
              'postal_code': customerPostalCode,
              'address': customerAddress,
              'phone': customerPhone,
            },
          );
          customerName = contact['name']!;
          customerPostalCode = contact['postal_code']!;
          customerAddress = contact['address']!;
          customerPhone = contact['phone']!;
        }
        if (customerName.isEmpty || customerAddress.isEmpty) {
          final customerId = invoice['customer_id']?.toString() ?? '';
          if (customerId.isNotEmpty) {
            try {
              // customers stores billing_address, not address/postal_code.
              // This optional same-company read retains the table's existing RLS.
              final customers = await _client
                  .from('customers')
                  .select('name, billing_address')
                  .eq('company_id', companyId)
                  .eq('id', customerId)
                  .limit(1);
              if (customers.isNotEmpty) {
                if (customerName.isEmpty) {
                  customerName =
                      customers.first['name']?.toString().trim() ?? '';
                }
                if (customerAddress.isEmpty) {
                  customerAddress =
                      customers.first['billing_address']?.toString().trim() ??
                      '';
                }
              }
            } catch (_) {
              // A related customer lookup must not hide the invoice.
            }
          }
        }
        if (customerName.isEmpty) customerName = '取引先未設定';

        final siteResults = <SiteInvoiceCalculation>[];
        final snapshotSites = snapshotMap['sites'];
        if (snapshotSites is List) {
          for (final rawSite in snapshotSites) {
            if (rawSite is! Map) continue;
            final siteMap = Map<String, dynamic>.from(rawSite);
            final siteId = siteMap['site_id']?.toString().trim() ?? '';
            final siteName = siteMap['site_name']?.toString().trim() ?? '';
            if (siteId.isEmpty || siteName.isEmpty) continue;

            final rawLines = siteMap['lines'];
            final displayLines = <InvoiceLine>[];
            if (rawLines is List) {
              for (final rawLine in rawLines) {
                if (rawLine is! Map) continue;
                final line = Map<String, dynamic>.from(rawLine);
                final sourceWorkContent = line['work_content']?.toString();
                final allowanceName =
                    line['allowance_name']?.toString().trim() ?? '';
                final workContent = allowanceName.isNotEmpty
                    ? '（$allowanceName）'
                    : sourceWorkContent;
                final sourceLabel = line['label']?.toString();
                final internalLabel = (workContent ?? '').trim().isNotEmpty
                    ? workContent!
                    : (sourceLabel ?? '').trim().isNotEmpty
                    ? sourceLabel!
                    : '通常作業';
                displayLines.add(
                  InvoiceLine(
                    label: internalLabel,
                    category: line['category']?.toString() ?? '',
                    quantity: _toDouble(line['quantity']),
                    unitPriceYen: _toInt(line['unit_price']),
                    siteLabel: line['site_label']?.toString() ?? '',
                    workContent: workContent,
                    unitPriceText: line['unit_price_text']?.toString(),
                    amountYenOverride: line['amount'] == null
                        ? null
                        : _toInt(line['amount']),
                  ),
                );
              }
            }

            siteResults.add(
              SiteInvoiceCalculation.fromSavedDetails(
                siteId: siteId,
                siteName: siteName,
                lines: displayLines,
                manualAdjustmentYen: _toInt(siteMap['manual_adjustment']),
                welfareRateBps: _toInt(siteMap['welfare_rate_bps']),
                subtotalYen: siteMap['subtotal'] == null
                    ? null
                    : _toInt(siteMap['subtotal']),
              ),
            );
          }
        }

        // Older manually-created invoices may not carry snapshot sites.
        // Hydrate normalized detail only in that case and keep failures local
        // to this optional path.
        if (siteResults.isEmpty) {
          try {
            final calculations = await _client
                .from('invoice_site_calculations')
                .select(
                  'id, site_id, manual_adjustment_amount, '
                  'welfare_rate_snapshot, subtotal',
                )
                .eq('company_id', companyId)
                .eq('invoice_id', invoiceId)
                .order('created_at');

            for (final calculation in calculations) {
              final calculationId = calculation['id']?.toString() ?? '';
              final siteId = calculation['site_id']?.toString() ?? '';
              if (calculationId.isEmpty || siteId.isEmpty) continue;

              var siteName = '';
              try {
                final sites = await _client
                    .from('sites')
                    .select('name')
                    .eq('company_id', companyId)
                    .eq('id', siteId)
                    .limit(1);
                if (sites.isNotEmpty) {
                  siteName = sites.first['name']?.toString().trim() ?? '';
                }
              } catch (_) {
                // Keep optional normalized hydration isolated.
              }
              if (siteName.isEmpty) continue;

              var lines = <dynamic>[];
              try {
                lines = await _client
                    .from('invoice_detail_lines')
                    .select(
                      'description, quantity, unit_price, amount, category',
                    )
                    .eq('company_id', companyId)
                    .eq('invoice_site_calculation_id', calculationId)
                    .order('sort_order');
              } catch (_) {
                // An unavailable detail relation should not hide the invoice.
              }

              siteResults.add(
                SiteInvoiceCalculation.fromSavedDetails(
                  siteId: siteId,
                  siteName: siteName,
                  lines: lines
                      .map<InvoiceLine>(
                        (line) => InvoiceLine(
                          label: line['description']?.toString() ?? '明細',
                          category: line['category']?.toString() ?? '',
                          amountYenOverride: line['amount'] == null
                              ? null
                              : _toInt(line['amount']),
                          quantity: _toDouble(line['quantity']),
                          unitPriceYen: _toInt(line['unit_price']),
                        ),
                      )
                      .toList(),
                  manualAdjustmentYen: _toInt(
                    calculation['manual_adjustment_amount'],
                  ),
                  welfareRateBps:
                      (_toDouble(calculation['welfare_rate_snapshot']) * 100)
                          .round(),
                  subtotalYen: calculation['subtotal'] == null
                      ? null
                      : _toInt(calculation['subtotal']),
                ),
              );
            }
          } catch (_) {
            // Zero-site drafts and snapshot-only invoices are still valid.
          }
        }

        final periodStart = DateTime.tryParse(
          invoice['billing_period_start']?.toString() ?? '',
        );
        final periodEnd = DateTime.tryParse(
          invoice['billing_period_end']?.toString() ?? '',
        );
        final issueDate = DateTime.tryParse(
          invoice['issue_date']?.toString() ?? '',
        );
        final billingPeriod = periodStart == null
            ? snapshotMap['billing_period']?.toString().trim() ?? ''
            : '${periodStart.year}年${periodStart.month}月';
        if (billingPeriod.isEmpty) continue;

        results.add(
          InvoiceEngine.calculate(
            customerId: customerName,
            customerPostalCode: customerPostalCode,
            customerAddress: customerAddress,
            customerPhone: customerPhone,
            billingPeriod: billingPeriod,
            detailMode: _fromDbDetailMode(invoice['detail_mode']?.toString()),
            sites: siteResults,
            taxRateBps:
                snapshotMap['tax_rate_bps'] != null &&
                    _toInt(snapshotMap['tax_rate_bps']) >= 0
                ? _toInt(snapshotMap['tax_rate_bps'])
                : _taxRateFromTotals(
                    subtotal: _toInt(invoice['subtotal']),
                    tax: _toInt(invoice['tax']),
                  ),
            invoiceId: invoiceId,
            documentUpdatedAt: invoice['updated_at']?.toString(),
            companySealSnapshot: invoiceDocumentSeal(
              document: invoice,
              saved: snapshotMap['company_seal_snapshot'],
              currentCompany: currentSealCompany,
              companyId: companyId,
            ),
            invoiceNumber: invoice['invoice_number']?.toString() ?? '',
            issueDate: issueDate,
            periodStart: periodStart,
            periodEnd: periodEnd,
            subtotalYenOverride: _toInt(invoice['subtotal']),
            taxYenOverride: _toInt(invoice['tax']),
            grandTotalYenOverride: _toInt(invoice['grand_total']),
          ),
        );
      } catch (_) {
        // Keep other valid invoices visible even if one historical row is malformed.
      }
    }
    return results;
  }

  Future<void> insert(InvoiceCalculationResult invoice) async {
    final companyId = await _companyId();
    final period = _parseBillingPeriod(invoice.billingPeriod);

    final customers = await _client
        .from('customers')
        .select('id')
        .eq('company_id', companyId)
        .eq('name', invoice.customerId.trim())
        .limit(1);
    if (customers.isEmpty) {
      throw StateError('得意先「${invoice.customerId}」が得意先/現場データに登録されていません。');
    }
    final customerId = customers.first['id'] as String;

    final siteIds = <String, String>{};
    for (final site in invoice.siteCalculations) {
      final sites = await _client
          .from('sites')
          .select('id')
          .eq('company_id', companyId)
          .eq('name', site.siteName.trim())
          .limit(1);
      if (sites.isEmpty) {
        throw StateError('現場「${site.siteName}」が現場管理に登録されていません。');
      }
      siteIds[site.siteName] = sites.first['id'] as String;
    }

    final totalWelfare = invoice.siteCalculations.fold<int>(
      0,
      (sum, site) => sum + site.welfareAmountYen,
    );
    final totalAdjustments = invoice.siteCalculations.fold<int>(
      0,
      (sum, site) => sum + site.manualAdjustmentYen,
    );

    final insertedInvoice = await _client
        .from('invoices')
        .insert({
          'company_id': companyId,
          'customer_id': customerId,
          'billing_period_start': _date(period.start),
          'billing_period_end': _date(period.end),
          'status': 'draft',
          'subtotal': invoice.subtotalYen,
          'tax': invoice.taxYen,
          'welfare_amount': totalWelfare,
          'adjustments': totalAdjustments,
          'grand_total': invoice.grandTotalYen,
          'detail_mode': _toDbDetailMode(invoice.detailMode),
          'snapshot': _snapshot(invoice),
        })
        .select('id')
        .single();
    final invoiceId = insertedInvoice['id'] as String;

    for (final site in invoice.siteCalculations) {
      final siteId = siteIds[site.siteName]!;
      final quantity = site.lines.fold<double>(
        0,
        (sum, line) => sum + line.quantity,
      );
      final unitPrice = site.lines.length == 1
          ? site.lines.first.unitPriceYen
          : 0;
      final insertedCalculation = await _client
          .from('invoice_site_calculations')
          .insert({
            'company_id': companyId,
            'invoice_id': invoiceId,
            'site_id': siteId,
            'calculation_method': 'manual_lines',
            'quantity_or_man_days': quantity,
            'unit_price': unitPrice,
            'manual_adjustment_amount': site.manualAdjustmentYen,
            'subtotal': site.subtotalYen,
            'tax_rate_snapshot': invoice.taxRateBps / 100,
            'welfare_rate_snapshot': site.welfareRateBps / 100,
          })
          .select('id')
          .single();
      final calculationId = insertedCalculation['id'] as String;

      for (var index = 0; index < site.lines.length; index++) {
        final line = site.lines[index];
        await _client.from('invoice_detail_lines').insert({
          'company_id': companyId,
          'invoice_site_calculation_id': calculationId,
          'description': line.label,
          'quantity': line.quantity,
          'unit': '人工',
          'unit_price': line.unitPriceYen,
          'amount': line.amountYen,
          'category': 'work',
          'sort_order': index,
        });
      }
    }
  }

  InvoiceDetailMode _fromDbDetailMode(String? value) => switch (value) {
    'site_breakdown_on_invoice' => InvoiceDetailMode.siteBreakdownOnInvoice,
    'site_breakdown_attachment' => InvoiceDetailMode.siteDetailAttachment,
    _ => InvoiceDetailMode.consolidatedOnly,
  };

  String _toDbDetailMode(InvoiceDetailMode mode) => switch (mode) {
    InvoiceDetailMode.consolidatedOnly => 'consolidated_only',
    InvoiceDetailMode.siteBreakdownOnInvoice => 'site_breakdown_on_invoice',
    InvoiceDetailMode.siteDetailAttachment => 'site_breakdown_attachment',
  };

  ({DateTime start, DateTime end}) _parseBillingPeriod(String value) {
    final normalized = value
        .trim()
        .replaceAll('年', '/')
        .replaceAll('月', '')
        .replaceAll('-', '/');
    final parts = normalized
        .split('/')
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length < 2) {
      throw StateError('対象期間は「2026年9月」または「2026/9」の形式で入力してください。');
    }
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    if (year == null || month == null || month < 1 || month > 12) {
      throw StateError('対象期間を正しく入力してください。');
    }
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 0);
    return (start: start, end: end);
  }

  int _taxRateFromTotals({required int subtotal, required int tax}) {
    if (subtotal <= 0 || tax <= 0) return 1000;
    return (tax * 10000 / subtotal).round();
  }

  Map<String, dynamic> _snapshot(InvoiceCalculationResult invoice) => {
    'customer_name': invoice.customerId,
    'customer_postal_code': invoice.customerPostalCode,
    'customer_address': invoice.customerAddress,
    'customer_phone': invoice.customerPhone,
    'billing_period': invoice.billingPeriod,
    'detail_mode': _toDbDetailMode(invoice.detailMode),
    'tax_rate_bps': invoice.taxRateBps,
    'subtotal': invoice.subtotalYen,
    'tax': invoice.taxYen,
    'grand_total': invoice.grandTotalYen,
    'sites': invoice.siteCalculations
        .map(
          (site) => {
            'site_name': site.siteName,
            'manual_adjustment': site.manualAdjustmentYen,
            'welfare_rate_bps': site.welfareRateBps,
            'subtotal': site.subtotalYen,
            'lines': site.lines
                .map(
                  (line) => {
                    'label': line.label,
                    'quantity': line.quantity,
                    'unit_price': line.unitPriceYen,
                    'amount': line.amountYen,
                    'site_label': line.siteLabel,
                    'work_content': line.workContent ?? line.label,
                    'unit_price_text':
                        line.unitPriceText ?? line.unitPriceYen.toString(),
                  },
                )
                .toList(),
          },
        )
        .toList(),
  };

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  int _toInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  double _toDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}
