import 'dart:convert';

import '../../domain/company_seal_snapshot.dart';
import '../../domain/trade_document_form_draft.dart';
import '../../domain/trade_document_terms_snapshot.dart';
import 'site_order_outgoing_journal.dart';

Map<String, dynamic> _copy(Map value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
Object? _ordered(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final key in keys) key: _ordered(value[key])};
  }
  if (value is List) return value.map(_ordered).toList(growable: false);
  return value;
}

bool _same(Object? a, Object? b) =>
    jsonEncode(_ordered(a)) == jsonEncode(_ordered(b));

/// Converts an already verified site source into a RAM-only editor model.
/// This is not an authorization receipt or a persistence/send API. The caller
/// must recheck its captured actor/company/session and source before each use.
class SiteOrderOutgoingBodyFactory {
  SiteOrderOutgoingBodyFactory({
    required Map<String, dynamic> verifiedContext,
    required String actorId,
    required String companyId,
    required this.pending,
    required Map<String, dynamic> termsSnapshot,
  }) : _context = _copy(verifiedContext),
       _terms = _copy(termsSnapshot) {
    for (final id in [actorId, companyId]) {
      if (!SiteOrderPendingPrepare.validId(id)) _invalid();
    }
    if (_context['contract_version'] != 1 ||
        _context['actor_id'] != actorId ||
        _context['session_id'] != pending.sessionId ||
        _context['company_id'] != companyId ||
        _context['site_id'] != pending.siteId ||
        _context['trade_company_id'] != pending.tradeId ||
        !SiteOrderPendingPrepare.validId(_context['counterparty_company_id']) ||
        _context['counterparty_company_id'] == companyId ||
        _context['creates_document'] != false ||
        _context['records_consent'] != false ||
        _context['can_send'] != false ||
        _context['issuer'] is! Map ||
        _context['counterparty'] is! Map ||
        _context['site'] is! Map ||
        _context['own_seal'] is! Map) {
      _invalid();
    }
    for (final key in ['issuer', 'counterparty']) {
      final party = _context[key] as Map;
      if (party['name'] is! String ||
          (party['name'] as String).trim().isEmpty ||
          party.values.any((v) => v is! String)) {
        _invalid();
      }
    }
    final seal = (_context['own_seal'] as Map)['snapshot'];
    final parsed = CompanySealSnapshot.fromJson(seal);
    if (parsed.name != (_context['issuer'] as Map)['name'] ||
        (parsed.companyId != null && parsed.companyId != companyId)) {
      _invalid();
    }
    TradeDocumentTermsSnapshot.fromJson(_terms);
  }
  final SiteOrderPendingPrepare pending;
  final Map<String, dynamic> _context, _terms;
  static Never _invalid() => throw StateError('注文の会社・現場・契約条項を確認できません。');
  String _date(Object? value, {bool allowBlank = false}) {
    if (allowBlank && (value == null || value == '')) return '';
    if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      _invalid();
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null || parsed.toIso8601String().substring(0, 10) != value) {
      _invalid();
    }
    return value;
  }

  Map<String, dynamic> get _editorSeal => {
    'company_seal_snapshot': _copy(
      (_context['own_seal'] as Map)['snapshot'] as Map,
    ),
    'company_seal_enabled': true,
  };
  void _identity(Map<String, dynamic> body) {
    if (body['version'] != 1 ||
        body['kind'] != 'order' ||
        body['issuer_company_id'] != _context['company_id'] ||
        body['counterparty_company_id'] !=
            _context['counterparty_company_id'] ||
        body['transaction_id'] != pending.documentId ||
        !_same(body['issuer'], _context['issuer']) ||
        !_same(body['counterparty'], _context['counterparty'])) {
      _invalid();
    }
    TradeDocumentTermsSnapshot.fromJson(body['contract_terms']);
  }

  /// New document only. Missing rates, quantities or tax never become zero.
  /// The unchanged server prepare still requires expected_revision=0 and rejects
  /// an already existing document; this factory cannot make that decision.
  TradeDocumentFormDraft newEditor({required String issueDate}) {
    final issue = _date(issueDate), site = _context['site'] as Map;
    final body = <String, dynamic>{
      'version': 1,
      'kind': 'order',
      'month': issue.substring(0, 7),
      'issue_date': issue,
      'order_date': issue,
      'issuer_company_id': _context['company_id'],
      'counterparty_company_id': _context['counterparty_company_id'],
      'transaction_id': pending.documentId,
      'issuer': _copy(_context['issuer'] as Map),
      'counterparty': _copy(_context['counterparty'] as Map),
      'work_name': site['name'],
      'work_address': site['address'],
      'period_start': _date(site['period_start'], allowBlank: true),
      'period_end': _date(site['period_end'], allowBlank: true),
      'total_amount_yen': null,
      'tax_amount_yen': null,
      'payment_conditions': '工事完了確認後、乙の指定口座に振り込む。',
      'notes': '',
      'intro_text': '発注者（以下「甲」という）は、受注者（以下「乙」という）に対し、下記の通り工事を発注します。',
      'acceptance_text': '',
      'contract_terms': _copy(_terms),
      ..._editorSeal,
    };
    _identity(body);
    return TradeDocumentFormDraft.fromPayload(
      body,
      allowAmountEditing: true,
      initializeDefaults: true,
      initializeExtendedFields: true,
    );
  }

  /// Reopening a staged body never initializes defaults or rewrites received
  /// conditions/explicit blanks. Foreign or unknown historical terms reject.
  TradeDocumentFormDraft editorForPreparedBody(
    Map<String, dynamic> canonicalBody,
  ) {
    final body = _copy(canonicalBody);
    _identity(body);
    if (body.keys.any(
      const {
        'company_seal_snapshot',
        'company_seal_enabled',
        'seals',
        'approved_by',
        'actor_id',
      }.contains,
    )) {
      _invalid();
    }
    return TradeDocumentFormDraft.fromPayload({
      ...body,
      ..._editorSeal,
    }, allowAmountEditing: true);
  }

  /// The editor needs a seal snapshot for drawing. Canonical prepare forbids
  /// those two editor-only fields; the server obtains consent seals itself.
  Map<String, dynamic> canonicalForPrepare(TradeDocumentFormDraft draft) {
    final body = draft.payload;
    _identity(body);
    if (!_same(
          body['company_seal_snapshot'],
          _editorSeal['company_seal_snapshot'],
        ) ||
        body['company_seal_enabled'] != true ||
        body.keys.any(const {'seals', 'approved_by', 'actor_id'}.contains)) {
      _invalid();
    }
    body.remove('company_seal_snapshot');
    body.remove('company_seal_enabled');
    // Validate the canonical body budget, not the editor's separate PNG asset.
    // Its real frozen snapshot was checked above; no substitute seal is added.
    TradeDocumentFormDraft.fromPayload(
      body,
      allowAmountEditing: true,
    ).validateForSave();
    return body;
  }
}
