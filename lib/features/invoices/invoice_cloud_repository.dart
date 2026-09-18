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
    final value = await membership();
    return value.role == 'owner' ||
        value.role == 'admin' ||
        value.role == 'manager';
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

  Future<List<InvoiceCalculationResult>> loadAll() async {
    final companyId = await _companyId();
    final invoices = await _client
        .from('invoices')
        .select('id, billing_period_start, detail_mode, subtotal, tax, grand_total, customers(name)')
        .eq('company_id', companyId)
        .order('billing_period_start', ascending: false)
        .order('created_at', ascending: false);

    final results = <InvoiceCalculationResult>[];
    for (final invoice in invoices) {
      final invoiceId = invoice['id'] as String;
      final customer = invoice['customers'];
      final customerName = customer is Map ? customer['name']?.toString() ?? '' : '';
      final calculations = await _client
          .from('invoice_site_calculations')
          .select('id, site_id, manual_adjustment_amount, welfare_rate_snapshot, sites(name)')
          .eq('company_id', companyId)
          .eq('invoice_id', invoiceId)
          .order('created_at');

      final siteResults = <SiteInvoiceCalculation>[];
      for (final calculation in calculations) {
        final calculationId = calculation['id'] as String;
        final site = calculation['sites'];
        final siteName = site is Map ? site['name']?.toString() ?? '' : '';
        final lines = await _client
            .from('invoice_detail_lines')
            .select('description, quantity, unit_price')
            .eq('company_id', companyId)
            .eq('invoice_site_calculation_id', calculationId)
            .order('sort_order');

        siteResults.add(
          SiteInvoiceCalculation(
            siteId: calculation['site_id']?.toString() ?? '',
            siteName: siteName,
            lines: lines
                .map<InvoiceLine>(
                  (line) => InvoiceLine(
                    label: line['description']?.toString() ?? '明細',
                    quantity: _toDouble(line['quantity']),
                    unitPriceYen: _toInt(line['unit_price']),
                  ),
                )
                .toList(),
            manualAdjustmentYen: _toInt(calculation['manual_adjustment_amount']),
            welfareRateBps: (_toDouble(calculation['welfare_rate_snapshot']) * 100).round(),
          ),
        );
      }

      final periodStart = DateTime.tryParse(invoice['billing_period_start']?.toString() ?? '');
      results.add(
        InvoiceEngine.calculate(
          customerId: customerName,
          billingPeriod: periodStart == null ? '' : '${periodStart.year}年${periodStart.month}月',
          detailMode: _fromDbDetailMode(invoice['detail_mode']?.toString()),
          sites: siteResults,
          taxRateBps: _taxRateFromTotals(
            subtotal: _toInt(invoice['subtotal']),
            tax: _toInt(invoice['tax']),
          ),
        ),
      );
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
      final quantity = site.lines.fold<double>(0, (sum, line) => sum + line.quantity);
      final unitPrice = site.lines.length == 1 ? site.lines.first.unitPriceYen : 0;
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
    final normalized = value.trim().replaceAll('年', '/').replaceAll('月', '').replaceAll('-', '/');
    final parts = normalized.split('/').where((part) => part.isNotEmpty).toList();
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
