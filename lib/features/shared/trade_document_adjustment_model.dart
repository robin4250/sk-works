import 'dart:convert';
import 'dart:math';

enum TradeDocumentAdjustmentKind {
  invoice('invoice', '取引会社', 'customer_id'),
  paymentCertificate('payment_certificate', '協力会社', 'partner_company_id');
  const TradeDocumentAdjustmentKind(this.value, this.partyLabel, this.partyField);
  final String value, partyLabel, partyField;
}

enum TradeDocumentAdjustmentSign {
  plus('plus', '＋ 加算'), minus('minus', '− 減算');
  const TradeDocumentAdjustmentSign(this.value, this.label);
  final String value, label;
}

enum TradeDocumentAdjustmentRecurrence {
  once('once', '今回だけ'), monthly('monthly', '毎月');
  const TradeDocumentAdjustmentRecurrence(this.value, this.label);
  final String value, label;
}

enum TradeDocumentAdjustmentCalculationMode {
  beforeCharges('before_charges', '既存の税・福利厚生を適用（計算前）'),
  settlementYen('settlement_yen', '入力額をそのまま加減算（追加税なし・最終額調整）');
  const TradeDocumentAdjustmentCalculationMode(this.value, this.label);
  final String value, label;
}

enum TradeDocumentAdjustmentAction { add, edit, cancel, stop }
enum TradeDocumentAdjustmentUpdateScope { currentMonth, fromMonth }

String tradeDocumentAdjustmentUuid(String value) {
  if (!RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$').hasMatch(value)) {
    throw const FormatException('会社・相手・保存先の識別情報を確認できません');
  }
  return value.toLowerCase();
}

String tradeDocumentAdjustmentMonth(String value) {
  if (!RegExp(r'^20\d{2}-(0[1-9]|1[0-2])-01$').hasMatch(value)) {
    throw const FormatException('対象月を確認できません');
  }
  return value;
}

String newTradeDocumentAdjustmentCommandId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final h = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

class TradeDocumentAdjustmentParty {
  TradeDocumentAdjustmentParty({required String id, required String companyId,
    required this.kind, required this.name})
      : id = tradeDocumentAdjustmentUuid(id), companyId = tradeDocumentAdjustmentUuid(companyId) {
    if (name.trim().isEmpty) { throw const FormatException('相手の会社名を確認できません'); }
  }
  final String id, companyId, name;
  final TradeDocumentAdjustmentKind kind;
}

class TradeDocumentAdjustmentEntry {
  TradeDocumentAdjustmentEntry({required String id, required this.title,
    required this.amountYen, required this.sign, required this.recurrence,
    required this.editable, required this.calculationMode, this.templateVersion, this.siteId, this.canStop = false, this.canceled = false,
    this.templateStopped = false, this.version = 1}) : id = tradeDocumentAdjustmentUuid(id) {
    if (title.trim().isEmpty || title.runes.length > 120 || amountYen < 1 ||
        amountYen > 2147483647 || version < 1 ||
        (templateVersion != null && (templateVersion! < 1 || templateVersion! > 2147483647))) {
      throw const FormatException('登録項目の内容を確認できません');
    }
    if (siteId != null) { tradeDocumentAdjustmentUuid(siteId!); }
  }
  final String id, title;
  final int amountYen, version;
  final int? templateVersion;
  final String? siteId;
  final TradeDocumentAdjustmentCalculationMode calculationMode;
  final TradeDocumentAdjustmentSign sign;
  final TradeDocumentAdjustmentRecurrence recurrence;
  final bool editable, canStop, canceled, templateStopped;
}

class TradeDocumentAdjustmentChargeSite {
  TradeDocumentAdjustmentChargeSite({required String id, required this.label})
      : id = tradeDocumentAdjustmentUuid(id);
  final String id, label;
}

class TradeDocumentAdjustmentWorkspace {
  TradeDocumentAdjustmentWorkspace({required String companyId, required this.kind,
    required String month, required List<TradeDocumentAdjustmentParty> parties,
    required List<TradeDocumentAdjustmentEntry> entries, required this.version,
    required this.ready, required this.canEdit, required this.taxMode,
    required Set<TradeDocumentAdjustmentCalculationMode> supportedModes,
    required List<TradeDocumentAdjustmentChargeSite> chargeSites,
    String? partyId, this.locked = false, this.lockedReason})
      : companyId = tradeDocumentAdjustmentUuid(companyId),
        month = tradeDocumentAdjustmentMonth(month),
        partyId = partyId == null ? null : tradeDocumentAdjustmentUuid(partyId),
        parties = List.unmodifiable(parties), entries = List.unmodifiable(entries),
        supportedModes = Set.unmodifiable(supportedModes), chargeSites = List.unmodifiable(chargeSites) {
    if (version < 0 || version > 2147483647 ||
        parties.any((p) => p.companyId != this.companyId || p.kind != kind) ||
        parties.map((p) => p.id).toSet().length != parties.length ||
        chargeSites.map((site) => site.id).toSet().length != chargeSites.length ||
        (this.partyId != null && !parties.any((p) => p.id == this.partyId)) ||
        (this.partyId == null && entries.isNotEmpty)) {
      throw const FormatException('会社・対象月・相手の組合せを確認できません');
    }
  }
  final String companyId, month, taxMode;
  final Set<TradeDocumentAdjustmentCalculationMode> supportedModes;
  final List<TradeDocumentAdjustmentChargeSite> chargeSites;
  final String? partyId, lockedReason;
  final TradeDocumentAdjustmentKind kind;
  final List<TradeDocumentAdjustmentParty> parties;
  final List<TradeDocumentAdjustmentEntry> entries;
  final int version;
  final bool ready, canEdit, locked;
  bool get canRegister => ready && canEdit && !locked &&
      supportedModes.isNotEmpty && partyId != null;
}

/// One immutable request is retained until its server receipt is known.
class TradeDocumentAdjustmentCommand {
  TradeDocumentAdjustmentCommand({required String commandId, required String companyId,
    required this.kind, required String partyId, required String month,
    required this.expectedVersion, required this.action, String? entryId,
    this.sign, String? title, this.amountYen, this.recurrence,
    required this.calculationMode, this.expectedTemplateVersion, String? siteId,
    String? effectiveMonth, this.updateScope = TradeDocumentAdjustmentUpdateScope.currentMonth})
      : commandId = tradeDocumentAdjustmentUuid(commandId),
        companyId = tradeDocumentAdjustmentUuid(companyId),
        partyId = tradeDocumentAdjustmentUuid(partyId),
        month = tradeDocumentAdjustmentMonth(month),
        entryId = entryId == null ? null : tradeDocumentAdjustmentUuid(entryId),
        siteId = siteId == null ? null : tradeDocumentAdjustmentUuid(siteId),
        title = title?.trim(),
        effectiveMonth = tradeDocumentAdjustmentMonth(effectiveMonth ?? month) {
    if (kind == TradeDocumentAdjustmentKind.invoice && calculationMode == TradeDocumentAdjustmentCalculationMode.beforeCharges && this.siteId == null) {
      throw const FormatException('対象現場を選択してください');
    }
    if (updateScope == TradeDocumentAdjustmentUpdateScope.fromMonth &&
        (expectedTemplateVersion == null || expectedTemplateVersion! < 1 || expectedTemplateVersion! > 2147483647)) {
      throw const FormatException('毎月設定の最新状態を確認してください');
    }
    if (expectedVersion < 0 || expectedVersion > 2147483647 ||
        (action != TradeDocumentAdjustmentAction.add && this.entryId == null) ||
        this.effectiveMonth.compareTo(this.month) < 0) {
      throw const FormatException('対象月と変更対象を確認してください');
    }
    if (action == TradeDocumentAdjustmentAction.add || action == TradeDocumentAdjustmentAction.edit) {
      if (sign == null || recurrence == null || this.title == null || this.title!.isEmpty ||
          this.title!.runes.length > 120 || amountYen == null || amountYen! < 1 || amountYen! > 2147483647) {
        throw const FormatException('項目名と1円以上の整数金額を入力してください');
      }
    }
    if (action == TradeDocumentAdjustmentAction.add &&
        (this.effectiveMonth != this.month || updateScope != TradeDocumentAdjustmentUpdateScope.currentMonth)) {
      throw const FormatException('追加する項目の開始月を確認してください');
    }
    if ((action == TradeDocumentAdjustmentAction.cancel &&
          (updateScope != TradeDocumentAdjustmentUpdateScope.currentMonth || this.effectiveMonth != this.month)) ||
        (updateScope == TradeDocumentAdjustmentUpdateScope.fromMonth &&
          action != TradeDocumentAdjustmentAction.edit && action != TradeDocumentAdjustmentAction.stop)) {
      throw const FormatException('変更する月の範囲を確認してください');
    }
  }
  final String commandId, companyId, partyId, month, effectiveMonth;
  final String? entryId, title, siteId;
  final int expectedVersion;
  final int? amountYen, expectedTemplateVersion;
  final TradeDocumentAdjustmentCalculationMode calculationMode;
  final TradeDocumentAdjustmentKind kind;
  final TradeDocumentAdjustmentAction action;
  final TradeDocumentAdjustmentSign? sign;
  final TradeDocumentAdjustmentRecurrence? recurrence;
  final TradeDocumentAdjustmentUpdateScope updateScope;
  Map<String, dynamic> toJson() => {
    'command_id': commandId, 'company_id': companyId, 'kind': kind.value,
    'party_id': partyId, 'month': month, 'expected_version': expectedVersion,
    'action': action.name, 'entry_id': entryId, 'sign': sign?.value,
    'title': title, 'amount_yen': amountYen, 'recurrence': recurrence?.value,
    'effective_month': effectiveMonth,
    'calculation_mode': calculationMode.value, 'site_id': siteId, 'expected_template_version': expectedTemplateVersion,
    'update_scope': updateScope == TradeDocumentAdjustmentUpdateScope.currentMonth ? 'current_month' : 'from_month',
  };
}

class TradeDocumentAdjustmentPreview {
  TradeDocumentAdjustmentPreview({required Map<String, dynamic> request,
    required this.token, required this.baseTotalYen, required this.resultTotalYen,
    this.welfareYen, this.taxYen, this.adjustmentYen})
      : request = Map.unmodifiable(request) {
    if (token.isEmpty) { throw const FormatException('計算結果を確認できません'); }
  }
  final Map<String, dynamic> request;
  final String token;
  final int baseTotalYen, resultTotalYen;
  final int? welfareYen, taxYen, adjustmentYen;
  void verify(TradeDocumentAdjustmentCommand command) {
    if (!_sameJson(request, command.toJson())) {
      throw const FormatException('入力内容と計算結果が一致しません');
    }
  }
}

class TradeDocumentAdjustmentReceipt {
  TradeDocumentAdjustmentReceipt({required Map<String, dynamic> request,
    required this.applied, required this.version, required String entryId,
    required this.previewToken, required this.resultTotalYen})
      : request = Map.unmodifiable(request), entryId = tradeDocumentAdjustmentUuid(entryId);
  final Map<String, dynamic> request;
  final bool applied;
  final String previewToken;
  final int resultTotalYen;
  final int version;
  final String entryId;
  void verify(TradeDocumentAdjustmentCommand command, TradeDocumentAdjustmentPreview preview) {
    preview.verify(command);
    if ((command.entryId != null && entryId != command.entryId) ||
        previewToken != preview.token || resultTotalYen != preview.resultTotalYen || !applied || version <= command.expectedVersion ||
        !_sameJson(request, command.toJson())) {
      throw const FormatException('登録結果と入力内容の一致を確認できません');
    }
  }
}

bool _sameJson(Object? a, Object? b) {
  if (a is Map && b is Map) {
    return a.length == b.length && a.keys.every((key) => b.containsKey(key) && _sameJson(a[key], b[key]));
  }
  if (a is List && b is List) {
    return a.length == b.length && Iterable<int>.generate(a.length).every((i) => _sameJson(a[i], b[i]));
  }
  return jsonEncode(a) == jsonEncode(b);
}

class TradeDocumentAdjustmentRejected implements Exception {
  const TradeDocumentAdjustmentRejected(this.message);
  final String message;
}

abstract class TradeDocumentAdjustmentPort {
  Future<TradeDocumentAdjustmentWorkspace> load({required String companyId,
    required TradeDocumentAdjustmentKind kind, required String month, String? partyId});
  Future<TradeDocumentAdjustmentPreview> preview(TradeDocumentAdjustmentCommand command);
  Future<TradeDocumentAdjustmentReceipt> apply(TradeDocumentAdjustmentCommand command,
    {required TradeDocumentAdjustmentPreview preview});
  Future<TradeDocumentAdjustmentReceipt?> lookup(TradeDocumentAdjustmentCommand command);
}
