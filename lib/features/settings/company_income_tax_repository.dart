import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';
import '../payroll/domain/company_rate_contract.dart';

const incomeTaxPdfBucket = 'company-income-tax-tables';
const incomeTaxPdfMaxBytes = 10 * 1024 * 1024;
const incomeTaxKinds = <String, String>{'monthly': '月額表', 'daily': '日額表', 'bonus': '賞与', 'computer_calculation': '電子計算'};

PayrollDate parseIncomeTaxDate(String text) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(text);
  if (match == null) throw const FormatException('日付はYYYY-MM-DDで入力してください');
  try {
    return PayrollDate(int.parse(match.group(1)!), int.parse(match.group(2)!), int.parse(match.group(3)!));
  } on ArgumentError {
    throw const FormatException('実在する日付を入力してください');
  }
}

String incomeTaxCivilDateText(PayrollDate date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

int _daysInMonth(int year, int month) {
  if (month == 2) return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) ? 29 : 28;
  return [4, 6, 9, 11].contains(month) ? 30 : 31;
}

String incomeTaxExclusiveEnd(String includedLastDay) {
  final date = parseIncomeTaxDate(includedLastDay);
  if (date.day < _daysInMonth(date.year, date.month)) return incomeTaxCivilDateText(PayrollDate(date.year, date.month, date.day + 1));
  if (date.month < 12) return incomeTaxCivilDateText(PayrollDate(date.year, date.month + 1, 1));
  return incomeTaxCivilDateText(PayrollDate(date.year + 1, 1, 1));
}

String incomeTaxIncludedLastDay(String exclusiveEnd) {
  final date = parseIncomeTaxDate(exclusiveEnd);
  if (date.day > 1) return incomeTaxCivilDateText(PayrollDate(date.year, date.month, date.day - 1));
  final year = date.month == 1 ? date.year - 1 : date.year;
  final month = date.month == 1 ? 12 : date.month - 1;
  return incomeTaxCivilDateText(PayrollDate(year, month, _daysInMonth(year, month)));
}

/// Upload did not return success and no metadata RPC was attempted.
/// The object may exist after a lost upload reply; no deletion or upsert follows.
class IncomeTaxUploadIncomplete implements Exception {
  const IncomeTaxUploadIncomplete();
}

Map<String, dynamic> _object(dynamic raw) {
  if (raw is! Map) throw const FormatException('税額表データを確認できません');
  return Map<String, dynamic>.from(raw);
}

bool incomeTaxValuesEqual(dynamic left, dynamic right) {
  if (left is Map && right is Map) {
    return left.length == right.length && left.keys.every((key) => right.containsKey(key) && incomeTaxValuesEqual(left[key], right[key]));
  }
  return left == right;
}

class IncomeTaxPdfFile {
  IncomeTaxPdfFile({required this.name, required List<int> bytes}) : bytes = Uint8List.fromList(bytes).asUnmodifiableView() {
    if (!name.toLowerCase().endsWith('.pdf') || bytes.length < 5 || bytes.length > incomeTaxPdfMaxBytes ||
        String.fromCharCodes(bytes.take(5)) != '%PDF-') {
      throw const FormatException('10MB以下のPDFファイルを選択してください');
    }
  }
  final String name;
  final Uint8List bytes;
}

class IncomeTaxUploadRequest {
  IncomeTaxUploadRequest._({required this.companyId, required this.tableId, required this.value, required this.file});
  final String companyId;
  final String tableId;
  final Map<String, dynamic> value;
  final IncomeTaxPdfFile file;
  factory IncomeTaxUploadRequest.create({required String companyId, required int year, required String kind,
    required String startsOn, required String endsOn, required String sourceUrl, required String publisher,
    required IncomeTaxPdfFile file}) {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    final id = '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
    final hash = sha256.convert(file.bytes).toString();
    final value = <String, dynamic>{'calendar_year': year, 'kind': kind, 'starts_on': startsOn, 'ends_before': incomeTaxExclusiveEnd(endsOn),
      'document_hash': hash, 'storage_path': '$companyId/$id/1/$hash.pdf',
      'source_url': sourceUrl.trim(), 'publisher': publisher.trim(), 'file_name': file.name};
    validateIncomeTaxValue(value, companyId, id, 1);
    return IncomeTaxUploadRequest._(companyId: companyId, tableId: id, value: Map.unmodifiable(value), file: file);
  }
}

Map<String, dynamic> validateIncomeTaxValue(dynamic raw, String companyId, String tableId, int version) {
  final value = _object(raw);
  final uuid = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');
  if (!uuid.hasMatch(companyId) || !uuid.hasMatch(tableId)) throw const FormatException('資料の会社情報を確認できません');
  final year = value['calendar_year'];
  if (year is! int || year < 1000 || year > 9998 || !incomeTaxKinds.containsKey(value['kind'])) {
    throw const FormatException('年度と税額表の種類を確認してください');
  }
  for (final key in ['starts_on', 'ends_before', 'document_hash', 'storage_path', 'source_url', 'publisher', 'file_name']) {
    if (value[key] is! String || (value[key] as String).trim().isEmpty) throw const FormatException('資料情報を確認してください');
  }
  final start = parseIncomeTaxDate(value['starts_on'] as String);
  final end = parseIncomeTaxDate(value['ends_before'] as String);
  final source = Uri.tryParse(value['source_url'] as String);
  final hash = value['document_hash'] as String;
  if (start.year != year || start.compareTo(end) >= 0 || end.compareTo(PayrollDate(year + 1, 1, 1)) > 0 ||
      source == null || source.scheme != 'https' || source.host.isEmpty ||
      (value['source_url'] as String).length > 2048 || RegExp(r'\s').hasMatch(value['source_url'] as String) ||
      (value['publisher'] as String).trim().length > 200 ||
      (value['file_name'] as String).length < 5 || (value['file_name'] as String).length > 200 ||
      !RegExp(r'^[0-9a-f]{64}$').hasMatch(hash) ||
      value['storage_path'] != '$companyId/$tableId/$version/$hash.pdf' ||
      !RegExp(r'^[^/\\]+\.pdf$', caseSensitive: false).hasMatch(value['file_name'] as String)) {
    throw const FormatException('年度・適用期間・PDFの情報を確認してください');
  }
  return Map.unmodifiable(value);
}

class CompanyIncomeTaxTable {
  const CompanyIncomeTaxTable({required this.id, required this.version, required this.value,
    required this.officialVerified, required this.rulesVerified, required this.registeredBy, required this.registeredAt});
  final String id;
  final int version;
  final Map<String, dynamic> value;
  final bool officialVerified;
  final bool rulesVerified;
  final String? registeredBy;
  final String registeredAt;
  factory CompanyIncomeTaxTable.fromJson(dynamic raw, String companyId) {
    final json = _object(raw);
    if (json['table_id'] is! String || json['version'] is! int || (json['version'] as int) < 1 ||
        json['official_document_verified'] is! bool || json['calculation_rules_verified'] is! bool ||
        json['common_data_approved'] != false || (json['registered_by'] != null && json['registered_by'] is! String) || json['registered_at'] is! String ||
        (json['calculation_rules_verified'] == true && json['official_document_verified'] != true)) {
      throw const FormatException('税額表の登録状態を確認できません');
    }
    final id = json['table_id'] as String;
    final version = json['version'] as int;
    return CompanyIncomeTaxTable(id: id, version: version, value: validateIncomeTaxValue(json['value'], companyId, id, version),
      officialVerified: json['official_document_verified'] as bool, rulesVerified: json['calculation_rules_verified'] as bool,
      registeredBy: json['registered_by'] as String?, registeredAt: json['registered_at'] as String);
  }
}

class CompanyIncomeTaxTablesData {
  const CompanyIncomeTaxTablesData({required this.tables, required this.selected, required this.history, this.canEdit = false});
  final bool canEdit;
  final List<CompanyIncomeTaxTable> tables;
  final CompanyIncomeTaxTable? selected;
  final List<Map<String, dynamic>> history;
  factory CompanyIncomeTaxTablesData.fromJson(dynamic raw, String companyId, String date, String kind) {
    final json = _object(raw);
    if (json['tables'] is! List || json['history'] is! List || !json.containsKey('selected')) {
      throw const FormatException('税額表一覧を確認できません');
    }
    final tables = (json['tables'] as List).map((row) => CompanyIncomeTaxTable.fromJson(row, companyId)).toList();
    final kindEnums = {'monthly': IncomeTaxTableKind.monthly, 'daily': IncomeTaxTableKind.daily,
      'bonus': IncomeTaxTableKind.bonus, 'computer_calculation': IncomeTaxTableKind.computerCalculation};
    final registry = IncomeTaxTableRegistry(companyId: companyId, registered: [for (final table in tables)
      IncomeTaxTableReference(tableId: table.id, ownerCompanyId: companyId, calendarYear: table.value['calendar_year'] as int,
        kind: kindEnums[table.value['kind']]!, startsOn: parseIncomeTaxDate(table.value['starts_on'] as String),
        endsBefore: parseIncomeTaxDate(table.value['ends_before'] as String),
        // Source URI is used solely for metadata scheduling validation, not PDF identity or payroll.
        pdf: Uri.parse(table.value['source_url'] as String), documentHash: table.value['document_hash'] as String,
        officialDocumentVerified: table.officialVerified, calculationRulesVerified: table.rulesVerified),
    ]);
    final selected = json['selected'] == null ? null : CompanyIncomeTaxTable.fromJson(json['selected'], companyId);
    final projected = registry.select(date: parseIncomeTaxDate(date), kind: kindEnums[kind]!);
    if (projected?.tableId != selected?.id) throw const FormatException('適用候補の資料を確認できません');
    final day = parseIncomeTaxDate(date);
    if (selected != null && (!selected.officialVerified || !selected.rulesVerified || selected.value['kind'] != kind ||
        selected.value['calendar_year'] != day.year || parseIncomeTaxDate(selected.value['starts_on'] as String).compareTo(day) > 0 ||
        day.compareTo(parseIncomeTaxDate(selected.value['ends_before'] as String)) >= 0 ||
        !tables.any((table) => table.id == selected.id && table.version == selected.version && incomeTaxValuesEqual(table.value, selected.value) &&
          table.officialVerified == selected.officialVerified && table.rulesVerified == selected.rulesVerified))) {
      throw const FormatException('適用候補の年度・検証状態を確認できません');
    }
    return CompanyIncomeTaxTablesData(canEdit: json['can_edit'] == true, tables: List.unmodifiable(tables), selected: selected,
      history: List.unmodifiable((json['history'] as List).map(_object)));
  }
}

abstract class CompanyIncomeTaxRepository {
  Future<CompanyIncomeTaxTablesData> read({required String companyId, required String date, required String kind});
  Future<CompanyIncomeTaxTable> registerPdf(IncomeTaxUploadRequest request);
  Future<String> pdfUrl(String storagePath);
}

typedef IncomeTaxRpc = Future<dynamic> Function(String name, Map<String, dynamic> parameters);
typedef IncomeTaxUpload = Future<void> Function(String path, Uint8List bytes);

class SupabaseCompanyIncomeTaxRepository implements CompanyIncomeTaxRepository {
  SupabaseCompanyIncomeTaxRepository({IncomeTaxRpc? rpc, IncomeTaxUpload? upload}) : _rpc = rpc, _upload = upload;
  final IncomeTaxRpc? _rpc;
  final IncomeTaxUpload? _upload;
  Future<dynamic> _call(String name, Map<String, dynamic> parameters) async {
    if (_rpc != null) return _rpc(name, parameters);
    return SupabaseBackend.client.rpc(name, params: parameters);
  }
  @override
  Future<CompanyIncomeTaxTablesData> read({required String companyId, required String date, required String kind}) async {
    final raw = await _call('read_company_income_tax_tables', {'p_company_id': companyId, 'p_payroll_date': date, 'p_kind': kind});
    return CompanyIncomeTaxTablesData.fromJson(raw, companyId, date, kind);
  }
  @override
  Future<CompanyIncomeTaxTable> registerPdf(IncomeTaxUploadRequest request) async {
    validateIncomeTaxValue(request.value, request.companyId, request.tableId, 1);
    if (sha256.convert(request.file.bytes).toString() != request.value['document_hash']) {
      throw const FormatException('選択したPDFの内容が変わっています');
    }
    final path = request.value['storage_path'] as String;
    try {
      if (_upload != null) {
        await _upload(path, request.file.bytes);
      } else {
        await SupabaseBackend.client.storage.from(incomeTaxPdfBucket).uploadBinary(path, request.file.bytes,
          fileOptions: FileOptions(contentType: 'application/pdf', upsert: false), retryAttempts: 0);
      }
    } catch (_) {
      throw const IncomeTaxUploadIncomplete();
    }
    final raw = await _call('register_company_income_tax_table', {
      'p_company_id': request.companyId, 'p_table_id': request.tableId, 'p_expected_version': 0,
      'p_value': request.value, 'p_confirmed': true,
    });
    final saved = CompanyIncomeTaxTable.fromJson(raw, request.companyId);
    if (saved.id != request.tableId || saved.version != 1 || !incomeTaxValuesEqual(saved.value, request.value) || saved.officialVerified || saved.rulesVerified) {
      throw const FormatException('登録結果を確認できません');
    }
    return saved;
  }
  @override
  Future<String> pdfUrl(String storagePath) => SupabaseBackend.client.storage.from(incomeTaxPdfBucket).createSignedUrl(storagePath, 600);
}
