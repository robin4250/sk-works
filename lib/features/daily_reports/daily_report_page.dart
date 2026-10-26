// ignore_for_file: prefer_interpolation_to_compose_strings

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import '../shared/pdf_bytes_cache.dart';
import 'daily_report_pdf_evidence.dart';
import 'daily_report_photo_pages.dart';
import 'daily_report_photo_preview.dart';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../notifications/notification_bell.dart';
import '../notifications/saved_group_report_publication.dart';
import '../notifications/saved_report_notification_retry_store.dart';
import '../../international/language_controller.dart';
import '../operations/odometer_text_recognition_engine.dart';
import 'daily_report_pdf_service.dart';
import 'daily_report_month_page.dart';
import '../operations/vehicle_driver_meter_page.dart';
import '../attendance/paid_work_hours_repository.dart';
import '../attendance/paid_work_hours_report_section.dart';
import 'daily_report_pending_notice.dart';
import 'daily_report_repository.dart';
import 'daily_report_allowance_name_field.dart';
import 'daily_report_company_allowance_selection.dart';
import '../shared/company_allowance_label_repository.dart';
import 'daily_report_edit_session.dart';
import 'signature_capture_page.dart';
import 'daily_report_zoom_pages.dart';
import 'route_visit_report_context.dart';
import 'daily_report_checkout_navigation.dart';
import 'shared_daily_report_repository.dart';
import 'shared_worker_facts_repository.dart';
import '../settings/company_work_category_repository.dart';

/// Keep technical exception wrappers out of report/save guidance.
String dailyReportActionErrorMessage(Object error) {
  if (error is SharedReportManagementHold) return error.message;
  if (error is FormatException && RegExp(r'[ぁ-んァ-ヶ一-龠]').hasMatch(error.message)) return error.message;
  if (error is StateError && RegExp(r'[ぁ-んァ-ヶ一-龠]').hasMatch(error.message.toString())) {
    return error.message.toString();
  }
  final raw = error.toString();
  const messages = {
    'employee_report_cannot_set_allowance_money': '保存済みの調整額は日報から変更・確定できません。金額を消さず、管理者の勤怠管理で確認してください。',
    'shared_report_manual_cash_requires_trusted_source': '保存済みの調整額の承認元を確認できません。金額や手当名を消さず、管理者の勤怠管理で確認してください。',
    'explicit_report_site_coordinator_unavailable': '当日の現場メンバーとして勤務実績を確認できません。日報を再読み込みし、管理者に確認してください。',
    'explicit_report_saved_preview_changed': '保存済みの日報と表示内容が一致しません。日報を再読み込みして確認してください。',
    'explicit_report_provisional_preparation_unavailable': '仮保存後の勤務実績を準備できる状態ではありません。日報を再読み込みして確認してください。',
    'explicit_report_closed_source_ambiguous': '対象者の出退勤記録が複数あり、勤務原本を決められません。管理者に確認してください。',
    'explicit_report_closed_source_invalid': '対象者の出退勤記録に矛盾があります。記録を移動・削除せず管理者に確認してください。',
    'explicit_report_source_binding_changed': '勤務原本と日報の関連付けが更新されました。日報を再読み込みして確認してください。',
    'shared_report_source_conflict': '勤務原本が別の日報に関連付いています。別の日報の記録は移動せず、管理者に確認してください。',
    'explicit_report_finalized_payroll_protected': '対象月の給与が確定済みのため保存できません。確定済みの給与は変更せず、管理者に確認してください。',
    'explicit_report_finalized_invoice_protected': '対象月の請求書が確定済みのため保存できません。確定済みの請求書は変更せず、管理者に確認してください。',
    'explicit_report_payroll_projection_missing': '給与への反映結果を確認できないため、日報の確定を保留しました。管理者に給与設定を確認してもらってください。',
    'explicit_report_invoice_projection_missing': '請求への反映結果を確認できないため、日報の確定を保留しました。管理者に請求先と請求設定を確認してもらってください。',
    'explicit_report_payroll_projection_blocked': '給与計算に必要な設定が不足しているため保存できません。管理者に個別給与設定と手当の設定を確認してもらってください。',
    'explicit_report_invoice_projection_blocked': '請求計算に必要な設定が不足しているため保存できません。管理者に請求先と現場の請求設定を確認してもらってください。',
    'explicit_report_financial_source_missing': '日報に対応する勤務実績を確認できません。対象者の出退勤と勤務日を管理者に確認してもらってください。',
    'explicit_report_invoice_customer_required': '現場・取引先の請求先設定を確認してください。サインは保存したままです。',
    'explicit_report_invoice_source_missing': '請求に必要な勤務の関連付けを確認できません。現場と取引先の設定を管理者に確認してもらってください。',
    'explicit_report_actual_facts_required': '②の勤務区分・勤務実績・必要な実勤務時間を確認してください。未確認の内容では確定できません。',
    'explicit_report_finalization_facts_pending': '対象メンバーの退勤と勤務実績の確認がまだそろっていません。②の入力内容を確認してください。',
    'explicit_report_edit_before_facts_change': 'サイン後の勤務実績を変更するには、先に「手直し」を押してください。変更後はサインの取り直しが必要です。',
    'explicit_report_actual_revision_required': '表示中の日報が更新されました。日報を再読み込みし、現在の内容を確認してください。',
    'explicit_report_finalization_disabled': '日報の確定処理は準備中です。管理者に確認してください。',
    'explicit_report_finalization_not_ready': '報告者・責任者のサインと勤務実績をそろえてから、⑤「保存して確定」を押してください。',
    'explicit_report_finalization_not_allowed': 'この日報を確定する権限を確認できません。当日の現場メンバーまたは管理者に確認してください。',
    'explicit_report_future_finance_not_supported': '未来日の給与・請求への確定は現在できません。勤務日を管理者に確認してください。',
    'explicit_report_confirmation_reason_invalid': '本人に代わって勤務実績を確認する理由を1〜1000文字で入力してください。',
    'signed_report_requires_existing_approved_edit': '確定済みの日報です。編集承認の手順、または管理者の勤怠管理から修正してください。',
    'shared_report_scope_changed': '日報の対象や勤務実績が更新されました。日報を再読み込みし、サイン対象を確認してください。',
    'explicit_route_scope_changed': '現場訪問の日報が更新されました。日報を再読み込みし、サイン対象を確認してください。',
    'explicit_route_finalization_disabled': '現場訪問日報の確定処理は準備中です。管理者に確認してください。',
    'explicit_route_finalization_not_ready': '報告者・責任者のサインをそろえてから、⑤「保存して確定」を押してください。',
    'explicit_route_finalization_not_allowed': 'この現場訪問日報を確定する権限を確認できません。当日の現場メンバーまたは管理者に確認してください。',
    'explicit_route_signature_already_saved': 'このサインは保存済みです。再読み込みして、⑤の確定状態を確認してください。',
    'explicit_route_edit_unavailable': 'この現場訪問日報は手直しできる状態ではありません。再読み込みし、管理者に確認してください。',
    'explicit_route_actor_required': 'ログイン状態を確認して、現場訪問の日報を開き直してください。',
    'explicit_route_membership_required': '当日の現場メンバーを確認できません。管理者に出勤と日報の関連付けを確認してもらってください。',
    'document_finance_transition_disabled': '勤務実績の連携は準備中です。サインせず管理者に確認してください。',
    'document_finance_audited_manager_required': '勤怠管理権限と、実績を確認する理由を確認してください。',
    'document_finance_closed_clocked_source_required': '対象者全員の実際の出退勤と、この日報への関連を確認してください。',
    'document_finance_explicit_unsigned_revision_required': '現在のサインと手直し状態を確認できません。日報を開き直してください。',
    'explicit_shared_worker_category_required': '勤務区分（日勤・夜勤など）を選んでください。',
    'company allowance registration changed': '選択済み手当と現在の登録・給与区分が一致しません。適用手当を選び直してください。',
    'paid_hours_input_conflict': '勤務原本が更新されました。入力内容を確認して再読み込みしてください。',
    'shared_report_signature_scope_changed': '日報またはサインの対象が更新されました。日報を開き直してください。',
    'shared_report_reporter_signature_required': '先に報告者サインを登録してください。',
    'shared_report_supervisor_not_ready': '全員の退勤と勤務実績の確認がそろってから責任者サインへ進んでください。',
    'shared_hours_supervisor_basis_changed_or_pending': '勤務実績が更新されたか、未確認のメンバーがいます。日報を再読み込みして確認してください。',
    'shared_report_signed_facts_require_approved_edit': 'サイン済みの内容を変更するには編集承認が必要です。',
  };
  for (final entry in messages.entries) {
    if (raw.contains(entry.key)) return entry.value;
  }
  return '保存を確認できませんでした。通信状態を確認し、日報を再読み込みしてください。';
}

class DailyReportPage extends StatefulWidget {
  const DailyReportPage({
    super.key,
    this.initialDate,
    this.initialSiteId,
    this.initialReportId,
    this.initialRouteAssignmentId,
    this.vehicleClockInId,
    this.groupClockInAnchorId,
    this.routeVisitContext,
    this.restrictedReporterRegistration = false,
    this.registrationActorId,
    this.registrationCompanyId,
    this.registrationWorkerId,
    this.onRegistrationSaved,
    this.onManageRegistration,
    @visibleForTesting this.repositoryForTesting,
    @visibleForTesting this.paidHoursRepositoryForTesting,
    @visibleForTesting this.sharedReportRepositoryForTesting,
    @visibleForTesting this.workerFactsRepositoryForTesting,
  });

  final bool restrictedReporterRegistration;
  final String? registrationActorId, registrationCompanyId, registrationWorkerId;
  final VoidCallback? onRegistrationSaved;
  final VoidCallback? onManageRegistration;
  final RouteVisitReportContext? routeVisitContext;
  @visibleForTesting
  final DailyReportRepository? repositoryForTesting;
  @visibleForTesting
  final PaidWorkHoursRepository? paidHoursRepositoryForTesting;
  @visibleForTesting
  final SharedDailyReportRepository? sharedReportRepositoryForTesting;
  @visibleForTesting
  final SharedWorkerFactsRepository? workerFactsRepositoryForTesting;

  final DateTime? initialDate;
  final String? initialSiteId;
  /// Saved report selection is pinned to its own identity, including same-day records.
  final String? initialReportId;
  final String? initialRouteAssignmentId;
  final String? vehicleClockInId;
  final String? groupClockInAnchorId;

  @override
  State<DailyReportPage> createState() => _DailyReportPageState();
}

class _DailyReportPageState extends State<DailyReportPage> {
  late final _repository = widget.repositoryForTesting ?? DailyReportRepository.maybeCreate();
  // Existing report-only fixtures explicitly inject their old repository.
  // Production never treats a missing hours API as zero/not required.
  late final _paidHoursRepository = widget.paidHoursRepositoryForTesting ??
      (widget.repositoryForTesting == null ? PaidWorkHoursRepository.maybeCreate() : null);
  late final _sharedReportRepository = widget.sharedReportRepositoryForTesting ??
      (widget.repositoryForTesting == null ? SharedDailyReportRepository.maybeCreate() : null);
  late final _workerFactsRepository = widget.workerFactsRepositoryForTesting ??
      (widget.repositoryForTesting == null ? SharedWorkerFactsRepository.maybeCreate() : null);
  late final _workCategoryRepository = widget.repositoryForTesting == null
      ? CompanyWorkCategoryRepository.maybeCreate() : null;
  SharedDailyReportContext? _sharedContext;
  bool _managementHoldWrite = false;
  String? _managementHoldWriteMessage;
  bool get _managementHold => _managementHoldWrite || _sharedContext?.isManagementHold == true;
  String get _managementHoldMessage => _managementHoldWriteMessage ??
      _sharedContext?.managementHoldMessage ?? '勤怠管理での確認が必要です。';
  void _rememberManagementHold(Object error) {
    if (mounted && error is SharedReportManagementHold) { setState(() { _managementHoldWrite = true; _managementHoldWriteMessage = error.message; }); }
  }
  String? _evidenceAttachmentFingerprint;
  final _workDescription = TextEditingController();
  final _picker = ImagePicker();
  final _odometerRecognition = const OdometerTextRecognitionEngine();

  late DateTime _date;
  List<DailyReportSiteGroup> _groups = const [];
  String? _siteId;
  String? _routeAssignmentId;
  String? _siteName;
  List<DailyReportWorkerDraft> _workers = [];
  List<CompanyAllowanceLabel> _companyAllowanceItems = const [];
  String? _companyAllowanceActor;
  Map<String, Set<String>> _companyAllowanceEligibility = const {};
  bool _companyAllowanceNamesLoading = false;
  bool _companyAllowanceNamesUnavailable = false;
  DailyReportRecord? _report;
  List<DailyReportEvidenceRecord> _evidence = const [];
  bool _loading = true;
  bool _saving = false;
  bool _approvedEditAvailable = false;
  final _editSessions = DailyReportEditSessionStore();
  DailyReportEditSession? _editSession;
  bool _editSessionUnverified = false;
  SignatureResult? _pendingResponsibleSignature;
  SharedDailyReportContext? _pendingSharedSignatureContext;
  String? _pendingSignatureFingerprint;
  String? _pendingReporterFingerprint;

  bool get _editingApprovedReport => !_visitReport && _editSession != null &&
      _editSession!.actorId == _repository?.currentActorId &&
      _editSession!.reportId == _report?.id;

  void _invalidatePendingSignature() {
    if (_pendingResponsibleSignature == null) {
      return;
    }
    setState(() {
      _pendingResponsibleSignature = null;
      _pendingSharedSignatureContext = null;
      _pendingSignatureFingerprint = null;
      _pendingReporterFingerprint = null;
    });
  }
  String? _notificationRetryReportId;
  final _notificationRetries = SavedReportNotificationRetryStore();
  SavedReportNotificationRetry? _notificationRetry;
  int _loadGeneration = 0;
  String? _savedDraftFingerprint;
  String? _error;

  final Map<String, TextEditingController> _confirmedHours = {};
  final _managementFactsReason = TextEditingController();
  final _allowanceFieldKeys = <String, GlobalKey>{};
  String? _preparedAllowanceWorkerId;
  final Map<String, TextEditingController> _overtime = {};
  final Map<String, TextEditingController> _early = {};
  final Map<String, TextEditingController> _night = {};
  final Map<String, TextEditingController> _allowanceLabel = {};
  final Map<String, TextEditingController> _odometer = {};

  bool get _visitReport => widget.routeVisitContext != null;
  bool get _registrationNavigationLocked => (widget.restrictedReporterRegistration || _visitReport) &&
      !(_report?.reporterSignatureJson != null && _report!.workDescription.trim().isNotEmpty &&
        (_visitReport || (_sharedContext?.reporterSaved == true && _sharedContext?.reportId == _report?.id &&
          _hasRegistrationSource(_workers, _sharedContext, _report?.id))));
  bool get _explicitFinalizationRequired => _visitReport
      ? _report?.visitFinalizationRequired == true : _sharedContext?.explicitFinalizationRequired == true;

  bool get _signed => _report?.signed == true;
  bool get _documentComplete => _sharedContext?.explicitFinalizationRequired != true &&
      _sharedContext?.documentOnly == true &&
      _sharedContext?.documentComplete == true && _sharedContext?.reportId == _report?.id &&
      _report?.reporterSignatureJson != null && _report?.responsibleSignatureJson != null;
  bool get _sharedFactsReadOnly => _sharedContext?.enabled == true &&
      _sharedContext!.signedFactsReadOnly && !_editingApprovedReport;
  bool get _partialSharedDraftAllowed => _sharedContext?.enabled == true &&
      (_sharedContext!.state == 'report_missing' || _sharedContext!.firstReporterCoversWorkOnly);

  String? get _currentGroupAnchor {
    final date = widget.initialDate;
    if (date == null || _siteId != widget.initialSiteId || _routeAssignmentId != null ||
        _date.year != date.year || _date.month != date.month || _date.day != date.day) {
      return null;
    }
    return widget.groupClockInAnchorId;
  }

  String? get _currentVehicleAnchor {
    final date = widget.initialDate;
    if (date == null || _siteId != widget.initialSiteId || _routeAssignmentId != widget.initialRouteAssignmentId ||
        _date.year != date.year || _date.month != date.month || _date.day != date.day) {
      return null;
    }
    return widget.vehicleClockInId;
  }

  bool get _visitReporterLocked => _visitReport &&
      (_report?.status == 'reporter_signed' || _report?.reporterSignatureJson != null);
  bool get _editable => _sharedContext?.financialTransitionPending != true && !_managementHold && !_signed && !_visitReporterLocked && !_sharedFactsReadOnly && !_saving;

  void _verifySharedContext(SharedDailyReportContext state, {String? reportId}) {
    if (state.actorId != _repository?.currentActorId ||
        state.workDate != DateTime(_date.year, _date.month, _date.day) ||
        (reportId != null && state.reportId != reportId) ||
        (widget.registrationCompanyId != null && state.companyId != widget.registrationCompanyId) ||
        (_report?.companyId != null && state.companyId != _report!.companyId)) {
      throw StateError('共同日報の本人・会社・勤務日が変わりました。開き直してください。');
    }
    final work = state.workBasis?['report'];
    if (work is Map && (work['site_id'] != _siteId || work['route_assignment_id'] != _routeAssignmentId)) {
      throw StateError('共同日報の現場・ルートが変わりました。開き直してください。');
    }
  }

  String _dailyStep(int step) => const ['①', '②', '③', '④', '⑤'][
    step - 1];

  bool _hasRegistrationSource(List<DailyReportWorkerDraft> workers,
      SharedDailyReportContext? shared, String? reportId) {
    final source = widget.vehicleClockInId;
    final workerId = widget.registrationWorkerId;
    final own = workers.where((worker) => worker.workerId == workerId).toList();
    if (source == null || workerId == null || own.length != 1) return false;
    if (own.single.sourceClockInId != null) {
      return own.single.sourceClockInId == source;
    }
    // Saved report rows do not carry clock-in IDs. A verified shared-source
    // response supplies that binding independently of optional group checkout.
    // Never assign a guessed source ID or change the saved/signed roster.
    if (shared == null || !shared.enabled ||
        shared.actorId != widget.registrationActorId ||
        shared.actorId != _repository?.currentActorId ||
        shared.companyId != widget.registrationCompanyId ||
        shared.workerId != workerId || shared.sourceClockInId != source ||
        shared.workDate != DateTime(_date.year, _date.month, _date.day)) { return false; }
    // resolve_own emits report_missing only after checking the unique exact
    // clock-out pair. That response intentionally has no report/clock-out ID.
    // The immutable destination came from the authoritative pending target.
    if (reportId == null) {
      return widget.initialReportId == null && shared.reportId == null &&
          shared.state == 'report_missing' && _siteId == widget.initialSiteId &&
          _routeAssignmentId == widget.initialRouteAssignmentId;
    }
    final header = shared.workBasis?['report'];
    return shared.clockOutId != null && shared.reportId == reportId &&
        const {'reporter_required', 'reporter_saved_waiting_supervisor',
          'supervisor_saved'}.contains(shared.state) &&
        shared.workRosterIds.contains(workerId) && header is Map &&
        header['site_id'] == _siteId && header['route_assignment_id'] == _routeAssignmentId;
  }

  Future<SharedDailyReportContext?> _readSharedContext({String? reportId}) async {
    if (_visitReport) return null;
    final repository = _sharedReportRepository;
    if (repository == null && widget.repositoryForTesting != null &&
        widget.sharedReportRepositoryForTesting == null) { return null; }
    if (repository == null) throw StateError('共同日報の提供状態を確認できません。');
    final source = _currentGroupAnchor ?? _currentVehicleAnchor;
    if (source == null && reportId == null) return null;
    final state = source == null
        ? await repository.loadReport(reportId!, expectedActor: _repository?.currentActorId)
        : await repository.loadForSource(source);
    _verifySharedContext(state, reportId: reportId);
    if (state.isManagementHold) { _sharedContext = state; }
    if (!state.isManagementHold) { _managementHoldWrite = false; _managementHoldWriteMessage = null; }
    return state;
  }

  @override
  void initState() {
    super.initState();
    final initial = widget.initialDate ?? DateTime.now();
    _date = DateTime(initial.year, initial.month, initial.day);
    _siteId = widget.initialSiteId;
    _routeAssignmentId = widget.routeVisitContext?.routeAssignmentId ?? widget.initialRouteAssignmentId;
    _workDescription.addListener(_invalidatePendingSignature);
    _loadDay();
    if (!_visitReport) _restoreNotificationRetry();
  }

  @override
  void dispose() {
    _workDescription.dispose();
    _managementFactsReason.dispose();
    _disposeWorkerControllers();
    super.dispose();
  }

  void _disposeWorkerControllers() {
    for (final controller in [
      ..._confirmedHours.values,
      ..._overtime.values,
      ..._early.values,
      ..._night.values,
      ..._allowanceLabel.values,
      ..._odometer.values,
    ]) {
      controller.dispose();
    }
    _confirmedHours.clear();
    _overtime.clear();
    _early.clear();
    _night.clear();
    _allowanceLabel.clear();
    _odometer.clear();
  }

  Future<void> _proposeWorkCategories(int generation) async {
    final repository = _workCategoryRepository;
    final companyId = _report?.companyId ?? _sharedContext?.companyId ?? widget.registrationCompanyId;
    final actor = _repository?.currentActorId;
    if (repository == null || companyId == null || actor == null || _signed ||
        _sharedFactsReadOnly || _workers.every((worker) => worker.workCategory != null)) { return; }
    try {
      final snapshot = await repository.load(companyId);
      for (final worker in _workers.where((worker) => worker.workCategory == null)) {
        final source = worker.sourceClockInId ?? (_sharedContext?.workerId == worker.workerId
          ? _sharedContext?.sourceClockInId : null);
        if (source == null) continue;
        final proposed = await repository.proposeForSource(snapshot,
          sourceClockInId: source, workerId: worker.workerId, workDate: _date);
        if (!mounted || generation != _loadGeneration || _repository?.currentActorId != actor ||
            (_report?.companyId ?? _sharedContext?.companyId ?? widget.registrationCompanyId) != companyId) { return; }
        if (worker.workCategory == null && proposed != null) setState(() => worker.workCategory = proposed);
      }
    } catch (_) {
      // A missing policy/source is not a guessed day shift. Keep manual input
      // available; saved categories and facts are never replaced.
    }
  }

  Future<void> _loadDay() async {
    if (_visitReport || widget.initialReportId != null) {
      await _loadSelectedSite();
      return;
    }
    final generation = ++_loadGeneration;
    final date = _date;
    final repository = _repository;
    if (repository == null) {
      setState(() {
        _loading = false;
        _error = SkoLanguageController.tr('日報機能を利用できません。');
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final groups = await repository.loadClockedInGroups(date);
      if (!mounted || generation != _loadGeneration) return;

      if (widget.restrictedReporterRegistration && repository.currentActorId != widget.registrationActorId) {
        throw const DailyReportActorChanged();
      }
      DailyReportSiteGroup? selected;
      if (_siteId != null) {
        selected = groups
            .where((g) => g.siteId == _siteId)
            .firstOrNull;
      } else if (_routeAssignmentId != null) {
        selected = groups
            .where((g) => g.routeAssignmentId == _routeAssignmentId)
            .firstOrNull;
      }
      if (widget.restrictedReporterRegistration && selected == null) {
        throw StateError('退勤した現場の日報を確認できません。対象を再確認してください。');
      }
      selected ??= groups.firstOrNull;

      setState(() {
        _groups = groups;
        _siteId = selected?.siteId;
        _routeAssignmentId = selected?.routeAssignmentId;
        _siteName = selected?.siteName;
      });

      await _loadSelectedSite();
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _error = dailyReportActionErrorMessage(error);
      });
    }
  }

  Future<void> _loadSelectedSite() async {
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _managementFactsReason.clear();
      _companyAllowanceItems = const [];
      _companyAllowanceActor = null;
      _companyAllowanceEligibility = const {};
      _companyAllowanceNamesLoading = false;
      _companyAllowanceNamesUnavailable = false;
    });
    final date = _date;
    final repository = _repository;
    final siteId = _siteId;
    final routeAssignmentId = _routeAssignmentId;
    if (repository == null ||
        (siteId == null && routeAssignmentId == null)) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _report = null;
        _workers = [];
        _evidence = const [];
        _loading = false;
      });
      _resetWorkerControllers();
      _savedDraftFingerprint = _draftFingerprint();
      return;
    }

    try {
      if (_visitReport) {
        final existing = await repository.loadVisitReport(
          widget.routeVisitContext!,
        );
        if (!mounted || generation != _loadGeneration) return;
        if (existing == null || (widget.initialReportId != null && existing.id != widget.initialReportId)) {
          throw StateError('現場訪問の日報を確認できません');
        }
        setState(() {
          _report = existing;
          _siteId = existing.siteId;
          _routeAssignmentId = existing.routeAssignmentId;
          _siteName = existing.siteName;
          _date = existing.date;
          _workers = existing.workers;
          _groups = [
            DailyReportSiteGroup(
              siteId: existing.siteId,
              routeAssignmentId: existing.routeAssignmentId,
              siteName: existing.siteName,
              workers: existing.workers,
            ),
          ];
          _evidence = const [];
          _workDescription.text = existing.workDescription;
          _loading = false;
          _error = null;
        });
        _resetWorkerControllers();
        _savedDraftFingerprint = _draftFingerprint();
        await _loadCompanyAllowanceNames(generation);
        return;
      }
      var shared = await _readSharedContext();
      if (mounted && generation == _loadGeneration) _sharedContext = shared;
      if (shared?.enabled == true && shared!.reporterSaved &&
          !shared.sourceAttached && shared.sourceClockInId != null && !shared.needsApprovedEdit) {
        shared = await _sharedReportRepository!.reuse(shared);
        _verifySharedContext(shared);
      }
      final selectedReportId = shared?.enabled == true && shared?.reportId != null
          ? shared!.reportId : widget.initialReportId;
      if (widget.initialReportId != null && selectedReportId != widget.initialReportId) {
        throw StateError('通知と保存済み日報の対象が一致しません。開き直してください。');
      }
      final existing = await repository.loadReport(
        date: date,
        siteId: siteId,
        routeAssignmentId: routeAssignmentId,
        vehicleClockInAnchorId: _currentVehicleAnchor,
        reportId: selectedReportId,
      );
      if (existing != null) shared = await _readSharedContext(reportId: existing.id);
      if (widget.restrictedReporterRegistration &&
          (repository.currentActorId != widget.registrationActorId ||
           (existing != null && existing.companyId != widget.registrationCompanyId))) {
        throw StateError('日報の本人・会社を確認できません。');
      }
      if (widget.initialReportId != null && existing?.id != widget.initialReportId) {
        throw StateError('選んだ保存済み日報を確認できません。日報一覧を再読み込みしてください。');
      }
      // Approval does not change a signed report until its owner explicitly
      // starts editing. Never erase signatures merely by opening this page.
      var approvedEditAvailable = false;
      if (existing?.signed == true) {
        try {
          approvedEditAvailable = await repository.hasApprovedEdit(existing!.id);
        } catch (_) {
          // A missing/denied capability must never unlock a report.
        }
      }
      DailyReportEditSession? editSession;
      var editSessionUnverified = false;
      final editActor = repository.currentActorId;
      if (existing != null && editActor != null) {
        try {
          final saved = await _editSessions.load(editActor, existing.id);
          editSessionUnverified = saved != null && !existing.signed;
          if (saved != null && saved.companyId == existing.companyId) {
            if (existing.signed) {
              await _editSessions.clear(saved);
            } else if (existing.status == 'draft' &&
                await repository.verifyEditSession(saved)) {
              editSession = saved;
              editSessionUnverified = false;
            }
          }
        } catch (_) {
          editSessionUnverified = !existing.signed;
          // Storage/network uncertainty cannot grant edit-session privileges.
        }
      }
      if (repository.currentActorId != editActor) {
        throw const DailyReportActorChanged();
      }
      final evidence = await repository.loadAttendanceEvidence(
        reportId: existing?.id,
        date: date,
        siteId: siteId,
        routeAssignmentId: routeAssignmentId,
      );
      if (!mounted || generation != _loadGeneration) return;

      final group = _groups
          .where(
            (g) =>
                g.siteId == siteId &&
                g.routeAssignmentId == routeAssignmentId,
          )
          .firstOrNull;
      var workers = existing?.workers.isNotEmpty == true
          ? existing!.workers
          : List<DailyReportWorkerDraft>.from(group?.workers ?? const []);
      final anchor = _currentGroupAnchor;
      if (anchor != null && shared?.financialTransitionPending != true &&
          !(shared?.enabled == true && shared!.signedFactsReadOnly)) {
        workers = await repository.loadAnchoredWorkers(anchorId: anchor, workDate: date,
          existing: workers, fallback: List<DailyReportWorkerDraft>.from(group?.workers ?? const [],
          ),
          allowNewMembers: existing?.signed != true,
        );
        if (!mounted || generation != _loadGeneration) return;
      }


      if (widget.restrictedReporterRegistration &&
          (repository.currentActorId != widget.registrationActorId ||
           !_hasRegistrationSource(workers, shared, existing?.id))) {
        throw StateError('退勤した本人の勤務原本を確認できません。');
      }
      final meterEnabled = await repository.vehicleMeterEnabledForAnchor(_currentVehicleAnchor,
      );
      if (meterEnabled) {
        for (final worker in workers.where((worker) => worker.vehicleId != null,
        )) {
          worker.meterManaged = true;
        }
      }
      if (!mounted || generation != _loadGeneration) return;

      setState(() {
        _error = null;
        _report = existing;
        _sharedContext = shared;
        _approvedEditAvailable = approvedEditAvailable;
        _editSession = editSession;
        _editSessionUnverified = editSessionUnverified;
        _siteName = existing?.siteName ?? group?.siteName ?? '';
        if (widget.initialReportId != null && existing != null) {
          _groups = [DailyReportSiteGroup(siteId: existing.siteId,
            routeAssignmentId: existing.routeAssignmentId, siteName: existing.siteName,
            workers: existing.workers)];
        }
        _workers = workers;
        _evidence = evidence;
        _workDescription.text = existing?.workDescription ?? '';
        _loading = false;
      });
      _resetWorkerControllers();
      _savedDraftFingerprint = _draftFingerprint();
      await _loadCompanyAllowanceNames(generation);
      await _proposeWorkCategories(generation);
      if (mounted && generation == _loadGeneration && shared?.sourceAttached == true &&
          shared?.reporterSaved == true) { widget.onRegistrationSaved?.call(); }
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _error = dailyReportActionErrorMessage(error);
      });
    }
  }

  Future<void> _loadCompanyAllowanceNames(int generation) async {
    final repository = _repository;
    // These are explicitly current registered names, not names effective on
    // the report date. Backdated unsigned entry may select them intentionally;
    // discovery never replaces existing text or edits a signed report.
    if (repository == null || _signed || _visitReporterLocked || _workers.isEmpty || _visitReport) { return; }
    final actor = repository.currentActorId;
    setState(() => _companyAllowanceNamesLoading = true);
    try {
      final snapshot = await repository.loadCompanyAllowanceLabels(
        workerIds: _workers.map((worker) => worker.workerId),
        expectedCompanyId: _report?.companyId);
      final reportId = _report?.id;
      final eligibility = reportId == null || reportId.isEmpty
          ? <String, Set<String>>{}
          : await repository.loadCompanyAllowanceEligibility(reportId: reportId,
              workerIds: _workers.map((worker) => worker.workerId), snapshot: snapshot);
      if (!mounted || generation != _loadGeneration ||
          repository.currentActorId != actor || _report?.id != reportId) {
        return;
      }
      setState(() {
        _companyAllowanceEligibility = eligibility;
        _companyAllowanceNamesUnavailable = false;
        _companyAllowanceActor = actor;
        _companyAllowanceItems = List.unmodifiable(snapshot.items);
        _companyAllowanceNamesLoading = false;
      });
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _companyAllowanceItems = const [];
        _companyAllowanceNamesLoading = false;
        _companyAllowanceNamesUnavailable = true;
      });
    }
  }

  void _resetWorkerControllers() {
    _disposeWorkerControllers();
    for (final worker in _workers) {
      final savedHours = _sharedContext?.hoursAnnexInputs
          .where((input) => input['worker_id'] == worker.workerId && input['confirmed'] == true)
          .firstOrNull?['hours'];
      _confirmedHours[worker.workerId] = TextEditingController(
        text: savedHours is num ? _number(savedHours.toDouble()) : '');
      _overtime[worker.workerId] =
          TextEditingController(text: _number(worker.overtimeHours),
      );
      _early[worker.workerId] =
          TextEditingController(text: _number(worker.earlyHours),
      );
      _night[worker.workerId] =
          TextEditingController(text: _number(worker.nightHours),
      );
      _allowanceLabel[worker.workerId] =
          TextEditingController(text: worker.allowanceLabel,
      );
      _odometer[worker.workerId] = TextEditingController(
        text: worker.odometerKm == null ? '' : _number(worker.odometerKm!),
      );
    }
    for (final controller in [
      ..._confirmedHours.values, ..._overtime.values, ..._early.values, ..._night.values,
      ..._allowanceLabel.values, ..._odometer.values,
    ]) {
      controller.addListener(_invalidatePendingSignature);
    }
  }

  Future<void> _pickDate() async {
    if (_saving || widget.initialReportId != null) return;
    final selected = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (selected == null || !mounted || _saving) return;
    setState(() {
      _date = selected;
      _siteId = null;
      _routeAssignmentId = null;
    });
    await _loadDay();
  }

  Future<void> _selectSite(String? destinationKey) async {
    if (destinationKey == null || _saving || !mounted || widget.initialReportId != null) return;
    final group = _groups
        .where((item) => item.destinationKey == destinationKey)
        .firstOrNull;
    if (group == null) return;
    if (group.siteId == _siteId &&
        group.routeAssignmentId == _routeAssignmentId) {
      return;
    }
    setState(() {
      _siteId = group.siteId;
      _routeAssignmentId = group.routeAssignmentId;
      _siteName = group.siteName;
      _loading = true;
    });
    await _loadSelectedSite();
  }

  double _optionalReportHours(TextEditingController? controller, String label) {
    final text = controller?.text.trim() ?? '';
    if (text.isEmpty) return 0;
    final value = double.tryParse(text);
    if (!RegExp(r'^(?:0|[1-9]\d?)(?:\.\d{1,4})?$').hasMatch(text) ||
        value == null || !value.isFinite || value < 0 || value > 24) {
      throw FormatException('$labelを0〜24の数値で入力してください。該当なしの場合は空欄にできます。');
    }
    return value;
  }

  void _applyControllers() {
    for (final worker in _workers) {
      worker.overtimeHours = _optionalReportHours(_overtime[worker.workerId], '残業時間');
      worker.earlyHours = _optionalReportHours(_early[worker.workerId], '早出時間');
      worker.nightHours = _optionalReportHours(_night[worker.workerId], '夜間時間');
      // Preserve the saved monetary value; employee reports do not edit money.
      worker.allowanceLabel =
          _allowanceLabel[worker.workerId]?.text.trim() ?? '';
      if (worker.vehicleId != null && !worker.meterManaged) {
        worker.odometerKm = double.tryParse(
          _odometer[worker.workerId]?.text.trim() ?? '',
        );
      }
    }
  }

  String _draftFingerprint() {
    _applyControllers();
    return jsonEncode({
      'description': _workDescription.text.trim(),
      'workers': _workers.map((worker) => {
        ...worker.toRpcJson(),
        'vehicle_id': worker.vehicleId,
        'route_id': worker.routeId,
        'odometer_km': worker.odometerKm,
        'source_clock_in_id': worker.sourceClockInId,
        'source_clock_out_at': worker.sourceClockOutAt?.toIso8601String(),
        'vehicle_meter_event_id': worker.meterEventId,
        'vehicle_meter_source_clock_in_id': worker.meterSourceClockInId,
        'previous_odometer_km': worker.previousOdometerKm,
        'trip_distance_km': worker.tripDistanceKm,
      },
          ).toList(),
    });
  }

  Future<String?> _saveBeforeSignature() async {
    if (_sharedContext?.financialTransitionPending == true) { return _preparedFinancialReportId(); }
    if (_sharedFactsReadOnly) return _report?.id;
    if (_signed || _visitReporterLocked) return _report?.id;
    if (!_visitReport && _report?.id.isNotEmpty != true &&
        _sharedReportRepository != null && _partialSharedDraftAllowed) {
      // A verified own checkout may save an incomplete draft. Signing still
      // waits for the explicit server work-only contract returned afterward.
      final id = await _saveDraft(ownsBusyState: false, quiet: true);
      if (id == null || !mounted) return null;
    }
    if (_sharedContext?.firstReporterCoversWorkOnly != true && _workers.any((worker) => worker.meterManaged && worker.meterEventId == null,
    )) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
        SkoLanguageController.tr('運転手のメーター登録が未完了です。下書き保存後、登録を確認して日報を再読み込みしてください',
            ),
          ),
        ),
      );
      return null;
    }
    if (!_visitReport && _report?.id.isNotEmpty != true && _sharedReportRepository != null) {
      final savedId = await _saveDraft(ownsBusyState: false, quiet: true);
      if (savedId == null || !mounted) return null;
    }
    if (!_visitReport && _report?.id.isNotEmpty == true) {
      _sharedContext = await _readSharedContext(reportId: _report!.id);
      if (_sharedContext?.enabled == true &&
          const {'own_checkout_required', 'source_conflict', 'roster_membership_required'}
              .contains(_sharedContext!.state)) {
        throw StateError('本人の退勤と日報の対象メンバーを確認してから、サインしてください。');
      }
      if (_sharedFactsReadOnly) return _report?.id;
    }
    if (!mounted) return null;
    if (_sharedContext?.firstReporterCoversWorkOnly != true && _workers.any((worker) => worker.sourceClockInId != null && worker.sourceClockOutAt == null,
    )) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
        SkoLanguageController.tr('未退勤のメンバーがいます。下書き保存後、退勤を確認して日報を再読み込みしてください',
            ),
          ),
        ),
      );
      return null;
    }
    if (((_currentGroupAnchor != null && _workers.any((worker) => worker.sourceClockInId != null)) ||
         (_currentVehicleAnchor != null && _workers.any((worker) => worker.meterManaged))) &&
        _evidenceAttachmentFingerprint != _draftFingerprint()) {
      final id = await _saveDraft(ownsBusyState: false, quiet: true);
      if (_sharedContext?.firstReporterCoversWorkOnly != true && _workers.any((worker) => worker.meterManaged && worker.meterEventId == null,
      )) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
            SkoLanguageController.tr('運転手のメーター登録が未完了です。下書き保存後、登録を確認して日報を再読み込みしてください',
                ),
              ),
            ),
          );
        }
        return null;
      }
      return id;
    }
    if (_report != null &&
        _report!.id.isNotEmpty && _savedDraftFingerprint == _draftFingerprint()) {
      return _report!.id;
    }
    final id = await _saveDraft(ownsBusyState: false, quiet: true);
    if (_sharedContext?.firstReporterCoversWorkOnly != true && _workers.any((worker) => worker.meterManaged && worker.meterEventId == null,
    )) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
          SkoLanguageController.tr('運転手のメーター登録が未完了です。下書き保存後、登録を確認して日報を再読み込みしてください',
              ),
            ),
          ),
        );
      }
      return null;
    }
    return id;
  }

  Future<void> _checkPaidHoursBeforeSignature(
    String reportId, void Function() checkSigningContext, {bool forSupervisor = false}
  ) async {
    if (_visitReport) return;
    final repository = _paidHoursRepository;
    if (repository == null && widget.repositoryForTesting != null &&
        widget.paidHoursRepositoryForTesting == null) { return; }
    final companyId = _report?.companyId;
    if (repository == null || companyId == null || companyId.isEmpty) {
      throw StateError('実勤務時間の設定状況を確認できません。日報を再読み込みしてください。');
    }
    checkSigningContext();
    final values = await Future.wait([
      for (final worker in _workers) repository.load(companyId: companyId,
        workerId: worker.workerId, reportId: reportId),
    ]);
    if (!mounted) return;
    checkSigningContext();
    if (_report?.id != reportId || values.any((value) =>
        value.workDate != DateTime(_date.year, _date.month, _date.day))) {
      throw StateError('対象日報または勤務日が変わりました。日報を再読み込みしてください。');
    }
    final problem = paidWorkHoursSignatureProblem(values, forSupervisor: forSupervisor);
    if (problem != null) throw StateError(problem);
  }

  Future<void> _afterPaidHoursSaved() async {
    if (_saving) return;
    _invalidatePendingSignature();
    setState(() => _saving = true);
    try { await _loadSelectedSite(); }
    finally { if (mounted) setState(() => _saving = false); }
  }

  bool _sharedWorkMatchesEditor(SharedDailyReportContext state) {
    final roster = _workers.map((worker) => worker.workerId).toSet();
    return state.workBasis != null && state.workDescription.trim() == _workDescription.text.trim() &&
        roster.length == _workers.length && roster.length == state.workRosterIds.length &&
        state.workRosterIds.every(roster.contains);
  }

  Future<bool> _reviewSupervisorFacts(SharedDailyReportContext state) async {
    if (!state.enabled) return true;
    final names = {for (final worker in _workers) worker.workerId: worker.workerName};
    if (state.workBasis == null || state.workRosterIds.any((id) => !names.containsKey(id))) {
      throw StateError('サインする作業内容とメンバーを確認できません。日報を再読み込みしてください。');
    }
    final ready = state.canCollectSupervisor;
    final factsLines = <Widget>[];
    for (final input in state.hoursAnnexInputs) {
      final name = names[input['worker_id']];
      if (name == null) throw StateError('勤務実績の対象メンバーが変わりました。日報を再読み込みしてください。');
      if (input['confirmed'] != true || input['facts_current'] != true || input['source_current'] != true) {
        factsLines.add(Text('$name：本人の勤務実績の確認待ち'));
        continue;
      }
      final facts = SharedWorkerFacts.parse(input['worker_facts']);
      const categoryNames = {'day': '日勤', 'night': '夜勤', 'holiday': '休日勤務', 'holiday_night': '休日夜勤'};
      factsLines.add(Padding(padding: const EdgeInsets.only(top: 8), child: Text(
        '$name：${categoryNames[facts.workCategory]} / 残業 ${facts.overtimeHours}h / 早出 ${facts.earlyHours}h / 夜間 ${facts.nightHours}h')));
      if (input['hours_required'] == true) factsLines.add(Text('実勤務時間：${input['hours']}時間'));
      final choices = facts.companyAllowanceSelections.items;
      factsLines.add(Text(choices.isEmpty ? '会社手当：選択なし' :
        '会社手当：${choices.map((item) => '${item.nameSnapshot}（${item.unit == 'hour' ? '時間' : '日'}単位）').join('、')}'));
      if (facts.allowanceLabel?.isNotEmpty == true) factsLines.add(Text('手当：${facts.allowanceLabel}'));
      if (facts.allowanceAmount != 0) factsLines.add(Text('既存の調整額：${facts.allowanceAmount}円'));
      if (facts.vehicleId != null) factsLines.add(Text('退勤時の走行距離：${facts.odometerKm}km'));
    }
    return await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: Text(ready ? '責任者サインで確認する内容' : '責任者サインの前に確認が必要です'),
      content: SizedBox(width: 540, child: SingleChildScrollView(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(state.workDescription),
          const SizedBox(height: 8), Text('対象メンバー：${state.workRosterIds.map((id) => names[id]!).join('、')}'),
          if (state.pendingWorkerIds.isNotEmpty) Text('退勤の確認待ち：${state.pendingWorkerIds.map((id) => names[id] ?? '対象メンバー').join('、')}'),
          ...factsLines,
          if (!ready) const Padding(padding: EdgeInsets.only(top: 12), child: Text(
            '対象メンバーの退勤・本人の勤務実績・必要な時間の確認をそろえてから、責任者本人にサインしてもらってください。')),
          if (ready) const Padding(padding: EdgeInsets.only(top: 12), child: Text(
            'ここに表示した保存済みの作業内容と勤務実績を確認します。サイン中に記録が変わった場合は保存せず、再確認します。')),
        ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('閉じる')),
        if (ready) FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('この内容で責任者サインへ'))],
    )) ?? false;
  }

  Future<void> _captureOdometer(
    DailyReportWorkerDraft worker) async {
    final photo = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 92,
      maxWidth: 2400,
    );
    if (photo == null) return;

    OdometerRecognitionResult result;
    try {
      result = await _odometerRecognition.recognizeImagePath(photo.path);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(SkoLanguageController.trParams('メーターを読み取れませんでした: {error}', {'error': error,
            }),
          ),
        ),
      );
      return;
    }

    if (!mounted) return;
    final controller = TextEditingController(
      text: result.bestCandidate == null
          ? ''
          : _number(result.bestCandidate!),
    );

    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(SkoLanguageController.tr('メーター読取結果')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              SkoLanguageController.tr('数値が合っていれば登録してください。違う場合は手入力で修正するか、再撮影できます。',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true,
              ),
              decoration: InputDecoration(
                labelText: SkoLanguageController.tr('走行距離'),
                suffixText: 'km',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'retry'),
            child: Text(SkoLanguageController.tr('再撮影')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'use'),
            child: Text(SkoLanguageController.tr('この数値を登録')),
          ),
        ],
      ),
    );

    if (action == 'retry') {
      controller.dispose();
      await _captureOdometer(worker);
      return;
    }

    if (action == 'use') {
      final value = double.tryParse(controller.text.trim());
      if (value == null || value < 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(SkoLanguageController.tr('走行距離を数字で入力してください')),
            ),
          );
        }
      } else {
        _odometer[worker.workerId]?.text = _number(value);
        worker.odometerKm = value;
        if (mounted) setState(() {});
      }
    }
    controller.dispose();
  }

  // Only the explicit registration action publishes. Internal draft saves for
  // signatures, previews and reloads never publish notifications.
  Future<void> _register() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      if (_visitReport) { await _saveDraft(ownsBusyState: false); return; }
      final completeGroup = groupReportPublicationEligible(
        anchorSourceId: _currentGroupAnchor, siteId: _siteId,
        routeAssignmentId: _routeAssignmentId,
        roster: _workers.map((worker) => (
          sourceId: worker.sourceClockInId, clockOutAt: worker.sourceClockOutAt,
          ),
        ),
      );
      await registerSavedGroupReport(
        notificationEligible: completeGroup,
        save: () => _saveDraft(ownsBusyState: false),
        publish: (id) async {
          final retry = _report?.notificationRetryScope;
          if (retry == null || retry.reportId != id) {
            throw StateError('登録済み日報を確認できません');
          }
          await _publishSavedReport(retry);
        },
      );
    } catch (error) {
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(dailyReportActionErrorMessage(error)))); }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _restoreNotificationRetry() async {
    final userId = _repository?.notificationRetryUserId;
    if (userId == null) return;
    try {
      final pending = await _notificationRetries.load(userId);
      if (!mounted || _repository?.notificationRetryUserId != userId) return;
      setState(() {
        _notificationRetry = pending.firstOrNull;
        _notificationRetryReportId = _notificationRetry?.reportId;
      });
    } catch (_) {
      // Corrupt or unreadable storage is retained, never reset to an empty list.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
          SkoLanguageController.tr('保存済み通知の再確認情報を読み込めません。保存内容は保持しています'),
        ),
          ),
        );
      }
    }
  }

  Future<void> _publishSavedReport(SavedReportNotificationRetry retry) async {
    final repository = _repository;
    if (repository == null) return;
    try {
      final sent = await retryPersistedSavedReportNotification(retry,
        remember: _notificationRetries.remember,
        verifySaved: repository.verifySavedNotificationScope,
        publish: (id) {
          if (repository.notificationRetryUserId != retry.userId) {
            throw StateError('日報通知の利用者が変更されています');
          }
          return repository.publishSavedGroupReportNotifications(id);
        },
        confirmed: _notificationRetries.confirmed,
      );
      await _restoreNotificationRetry();
      if (!sent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
          SkoLanguageController.tr('日報は登録済みです。通知結果は未確認です。同じ日報の通知のみ再確認できます'),
        ),
          ),
        );
      }
    } catch (_) {
      await _restoreNotificationRetry();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
        SkoLanguageController.tr('日報は登録済みです。メンバー通知の結果は未確認です。通知のみ再確認できます'),
      ),
        ),
      );
    }
  }

  Future<void> _retrySavedReportNotification() async {
    final repository = _repository;
    final userId = repository?.notificationRetryUserId;
    if (_saving || _notificationRetry == null || repository == null || userId == null) return;
    setState(() => _saving = true);
    try {
      // Every stored identity is checked independently. OFF/zero for the oldest
      // report cannot block later pending reports; no new report is saved.
      final pending = await _notificationRetries.load(userId);
      for (final retry in pending) {
        if (!mounted || repository.notificationRetryUserId != userId) break;
        await _publishSavedReport(retry);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
          SkoLanguageController.tr('保存済み通知の再確認情報を読み込めません。保存内容は保持しています'),
        ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<String?> _saveDraft({bool ownsBusyState = true,
      DailyReportEditSession? approvedReset, bool quiet = false}) async {
    if (_sharedContext?.financialTransitionPending == true) { return _preparedFinancialReportId(); }
    if (_managementHold) return null;
    if (ownsBusyState && _saving) return null;
    final resettingApprovedReport = approvedReset != null && !_visitReport &&
        _signed && _approvedEditAvailable &&
        approvedReset.actorId == _repository?.currentActorId &&
        approvedReset.reportId == _report?.id &&
        approvedReset.companyId == _report?.companyId;
    if (approvedReset != null && !resettingApprovedReport) {
      throw StateError('承認済みの編集と対象日報を確認できません。');
    }
    if (_sharedFactsReadOnly && !resettingApprovedReport) return _report?.id;
    if (_visitReport && (_signed || _visitReporterLocked)) return null;
    final repository = _repository;
    final siteId = _siteId;
    final routeAssignmentId = _routeAssignmentId;
    if (repository == null ||
        (siteId == null && routeAssignmentId == null)) {
      return null;
    }

    if (widget.restrictedReporterRegistration &&
        (repository.currentActorId != widget.registrationActorId ||
         _siteId != widget.initialSiteId || _routeAssignmentId != widget.initialRouteAssignmentId ||
         !_hasRegistrationSource(_workers, _sharedContext, _report?.id))) {
      throw StateError('退勤した本人の勤務原本を確認できません。');
    }
    _applyControllers();

    final missingOdometer = _workers.where(
      (worker) => worker.vehicleId != null && !worker.meterManaged && worker.odometerKm == null,
    );
    if (!_visitReport && !_partialSharedDraftAllowed && missingOdometer.isNotEmpty) {
      final names = missingOdometer.map((worker) => worker.workerName).join('、');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            SkoLanguageController.trParams('{names} の退勤時走行距離を入力してください', {'names': names,
            }),
          ),
        ),
      );
      return null;
    }

    if (ownsBusyState) setState(() => _saving = true);
    try {
      final documentBefore = _sharedContext;
      final String id;
      if (!_visitReport && documentBefore?.documentOnly == true && !resettingApprovedReport) {
        final sharedRepository = _sharedReportRepository;
        if (sharedRepository == null || documentBefore!.reportId != _report?.id) {
          throw StateError('手直しする日報の保存先を確認できません。');
        }
        final saved = await sharedRepository.saveDocumentDraft(before: documentBefore,
          workDescription: _workDescription.text,
          workers: [for (final worker in _workers) worker.toRpcJson()]);
        if (repository.currentActorId != documentBefore.actorId || _report?.id != saved.reportId) {
          throw const DailyReportActorChanged();
        }
        _sharedContext = saved;
        id = saved.reportId!;
      } else {
        id = _visitReport
          ? await repository.saveVisitDraft(
              context: widget.routeVisitContext!,
              expectedReportId: _report?.id.isNotEmpty == true ? _report!.id : null,
              workDescription: _workDescription.text,
              workers: _workers,
            )
          : await repository.saveDraft(
        reportId: _report?.id,
        siteId: siteId,
        routeAssignmentId: routeAssignmentId,
        date: _date,
        workDescription: _workDescription.text,
        workers: _workers,
        groupClockInAnchorId: _currentGroupAnchor,
        vehicleClockInAnchorId: _currentVehicleAnchor,
      );
      }
      if (!mounted) return id;
      _evidenceAttachmentFingerprint = _draftFingerprint();
      if (!quiet) { ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('入力途中を保存しました。まだ確定していません。'))); }
      await _loadSelectedSite();
      if (!mounted || _error != null || _report?.id != id) return null;
      // Unsigned preparation is not reporter registration and never releases the gate.
      return id;
    } catch (error) {
      _rememberManagementHold(error);
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${SkoLanguageController.tr('登録できませんでした')}: ${dailyReportActionErrorMessage(error)}'),
        ),
      );
      return null;
    } finally {
      if (mounted && ownsBusyState) setState(() => _saving = false);
    }
  }

  Future<void> _prepareCompanyAllowanceChoices(String workerId) async {
    if (_saving || !_editable || _visitReport || _report?.id.isNotEmpty == true) return;
    if (_workDescription.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('①の作業内容を入力してから手当を選んでください。')));
      return;
    }
    final actor = _repository?.currentActorId;
    final date = _date, site = _siteId, route = _routeAssignmentId;
    if (actor == null) return;
    FocusScope.of(context).unfocus();
    setState(() { _saving = true; _preparedAllowanceWorkerId = workerId; });
    try {
      final id = await _saveDraft(ownsBusyState: false, quiet: true);
      if (!mounted) return;
      if (_repository?.currentActorId != actor || _date != date || _siteId != site || _routeAssignmentId != route) {
        throw const DailyReportActorChanged();
      }
      if (id == null || _report?.id != id || _report?.reporterSignatureJson != null ||
          _companyAllowanceNamesUnavailable || !_companyAllowanceEligibility.containsKey(workerId)) {
        throw StateError('手当の適用対象を確認できません。入力内容を保持して再読み込みしてください。');
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _repository?.currentActorId != actor || _report?.id != id) return;
        final target = _allowanceFieldKeys[workerId]?.currentContext;
        if (target != null) { unawaited(Scrollable.ensureVisible(target,
          alignment: 0.2, duration: const Duration(milliseconds: 200))); }
      });
    } catch (error) {
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(dailyReportActionErrorMessage(error)))); }
    } finally { if (mounted) setState(() => _saving = false); }
  }

  double? _enteredConfirmedHours(String workerId) {
    final text = _confirmedHours[workerId]?.text.trim() ?? '';
    if (text.isEmpty) return null;
    final value = double.tryParse(text);
    if (!RegExp(r'^(?:0|[1-9]\d?)(?:\.\d{1,4})?$').hasMatch(text) ||
        value == null || !value.isFinite || value < 0 || value > 24) {
      throw const FormatException('実勤務時間を0〜24の数値で入力してください。');
    }
    return value;
  }

  Future<void> _confirmPendingFactsBeforeSupervisor(SharedDailyReportContext state,
      void Function() checkSigningContext) async {
    final repository = _workerFactsRepository;
    if (!state.explicitFinalizationRequired || repository == null || state.reportId == null ||
        state.supervisorSaved) { return; }
    for (final worker in _workers) {
      final before = await repository.load(companyId: state.companyId,
        reportId: state.reportId!, workerId: worker.workerId);
      checkSigningContext();
      if (before.confirmed && before.current || before.sourceBlocked) continue;
      if (!before.editable && !before.canManageAttendance && !before.canCoordinateSiteReport) continue;
      final facts = before.proposedFacts;
      if (facts == null) throw StateError('${worker.workerName}さんの②勤務区分と手当を確認してください。');
      final coordinated = !before.isOwnWorker && before.canCoordinateSiteReport;
      final managed = !before.isOwnWorker && !coordinated;
      final reason = managed ? _managementFactsReason.text.trim() : null;
      if (managed && (reason == null || reason.isEmpty)) {
        throw const FormatException('本人に代わって勤務実績を確認する理由を入力してください。');
      }
      final saved = coordinated
        ? await repository.confirmSiteReportFacts(before, facts, hours: _enteredConfirmedHours(worker.workerId),
            reason: _managementFactsReason.text.trim())
        : await repository.confirm(before, facts,
            hours: _enteredConfirmedHours(worker.workerId), managementReason: reason);
      checkSigningContext();
      if (!saved.confirmed || !saved.current || saved.workerId != worker.workerId ||
          saved.reportId != state.reportId || saved.companyId != state.companyId) {
        throw StateError('勤務実績の保存結果を確認できません。再読み込みしてください。');
      }
    }
  }

  String _reporterSignatureSummary(Map<String, double?> enteredHours) {
    const categoryNames = {'day': '日勤', 'night': '夜勤', 'holiday': '休日勤務', 'holiday_night': '休日夜勤'};
    final lines = <String>[_workDescription.text.trim()];
    for (final worker in _workers) {
      final selected = worker.companyAllowanceSelections?.items;
      lines.add('${worker.workerName}：${categoryNames[worker.workCategory] ?? '勤務区分未確認'} / 残業${worker.overtimeHours}h / 早出${worker.earlyHours}h / 夜間${worker.nightHours}h');
      lines.add(selected == null ? '登録手当：未確認' : selected.isEmpty
        ? '登録手当：選択なし（保存済みの文字・調整額は保持）'
        : '登録手当：${selected.map((item) => item.nameSnapshot).join('、')}');
      if (worker.allowanceLabel.trim().isNotEmpty) lines.add('保存済みの手当名：${worker.allowanceLabel.trim()}');
      if (enteredHours[worker.workerId] != null) lines.add('実勤務時間：${enteredHours[worker.workerId]}時間');
    }
    lines.add('この内容を報告者サインで仮保存します。給与・請求への反映は⑤「保存して確定」の成功後です。');
    return lines.join('\n');
  }

  Future<void> _signReporter() async {
    if (_managementHold || _saving || _signed || _visitReporterLocked || _sharedFactsReadOnly) return;
    if (_workDescription.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('作業内容を入力してから報告者サインへ進んでください。')));
      return;
    }
    if (_sharedContext?.explicitFinalizationRequired == true &&
        _workers.any((worker) => worker.workCategory == null)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('②の勤務区分（日勤・夜勤など）を選んでください。')));
      return;
    }
    FocusScope.of(context).unfocus();
    _invalidatePendingSignature();
    final signingActor = _repository?.currentActorId;
    final signingDate = _date;
    final signingSite = _siteId;
    final signingRoute = _routeAssignmentId;
    void checkSigningContext() {
      if (signingActor == null ||
          _repository?.currentActorId != signingActor ||
          _date != signingDate ||
          _siteId != signingSite ||
          _routeAssignmentId != signingRoute) {
        throw const DailyReportActorChanged();
      }
    }

    setState(() => _saving = true);
    try {
      final enteredConfirmationReason = _managementFactsReason.text.trim();
      final enteredHours = <String, double?>{
        for (final worker in _workers) worker.workerId: _enteredConfirmedHours(worker.workerId),
      };
      final reportId = await _saveBeforeSignature();
      if (reportId == null || !mounted) return;
      checkSigningContext();
      if (_sharedFactsReadOnly) {
        await _loadSelectedSite();
        if (mounted) widget.onRegistrationSaved?.call();
        return;
      }
      await _checkPaidHoursBeforeSignature(reportId, checkSigningContext);
      if (!mounted) return;
      checkSigningContext();
      var sharedBefore = _sharedContext;
      if (sharedBefore?.explicitFinalizationRequired == true &&
          _workers.any((worker) => worker.workCategory == null)) {
        throw const FormatException('②の勤務区分（日勤・夜勤など）を選んでください。');
      }
      if (sharedBefore?.explicitFinalizationRequired == true &&
          _workers.any((worker) => worker.companyAllowanceSelections == null)) {
        if (_companyAllowanceActor != signingActor || _companyAllowanceNamesLoading ||
            _companyAllowanceNamesUnavailable || _workers.any((worker) => !_companyAllowanceEligibility.containsKey(worker.workerId))) {
          throw StateError('②の会社手当の候補を確認できません。選択なしとして扱わず、日報を再読み込みしてください。');
        }
        for (final worker in _workers.where((worker) => worker.companyAllowanceSelections == null)) {
          worker.companyAllowanceSelections = DailyReportCompanyAllowanceSelections([]);
        }
        final savedId = await _saveDraft(ownsBusyState: false, quiet: true);
        if (!mounted) return;
        checkSigningContext();
        if (savedId != reportId || _report?.id != reportId || _error != null) {
          throw StateError('サイン前の入力内容を保存できません。日報を再読み込みしてください。');
        }
        sharedBefore = _sharedContext;
        if (sharedBefore?.explicitFinalizationRequired != true || sharedBefore?.reporterSaved == true ||
            sharedBefore?.supervisorSaved == true) {
          throw StateError('サイン対象の日報が更新されました。日報を再読み込みしてください。');
        }
      }
      if (sharedBefore?.firstReporterCoversWorkOnly == true &&
          (_workDescription.text.trim().isEmpty || _workers.isEmpty || !_sharedWorkMatchesEditor(sharedBefore!))) {
        throw StateError('作業内容とメンバーが更新されています。保存済みの日報を再読み込みして確認してください。');
      }
      final result = await Navigator.of(context).push<SignatureResult>(
        MaterialPageRoute(builder: (_) => SignatureCapturePage(
          title: SkoLanguageController.tr('報告者サイン'),
          signerLabel: SkoLanguageController.tr('報告者名'),
          submitLabel: SkoLanguageController.tr('報告者サインを保存'),
          initialSignerName: _report?.reporterSignerName ?? '',
          reviewText: sharedBefore?.explicitFinalizationRequired == true
            ? _reporterSignatureSummary(enteredHours) : null,
          signerNameOptions: [for (final worker in _workers) worker.workerName,
            ],
          ),
        ),
      );
      if (result == null || !mounted) return;
      checkSigningContext();
      if (_report?.id != reportId) throw StateError('対象日報が変わりました');
      final repository = _repository;
      if (repository == null) return;
      if (sharedBefore?.enabled == true && !_editingApprovedReport) {
        final sharedRepository = _sharedReportRepository!;
        final SharedDailyReportContext resultState;
        if (sharedBefore!.sourceClockInId != null) {
          _applyControllers();
          resultState = await sharedRepository.submit(before: sharedBefore,
            workDescription: _workDescription.text,
            workers: [for (final worker in _workers) {...worker.toRpcJson(),
              if (sharedBefore.explicitFinalizationRequired) 'confirmed_hours': enteredHours[worker.workerId],
              if (sharedBefore.explicitFinalizationRequired) 'confirmation_reason':
                worker.workerId == sharedBefore.workerId || enteredConfirmationReason.isEmpty ? null : enteredConfirmationReason}],
            signerName: result.signerName, signature: {'strokes': result.toJson()});
        } else {
          resultState = await sharedRepository.manageSignature(before: sharedBefore,
            role: 'representative', signerName: result.signerName, signature: {'strokes': result.toJson()});
        }
        _verifySharedContext(resultState, reportId: reportId);
        if (!resultState.reporterSaved) throw StateError('報告者サインの保存を確認できません。再読込してください。');
        _sharedContext = resultState;
      } else if (_visitReport) {
        await repository.signVisit(
          reportId: reportId,
          role: 'reporter',
          signerName: result.signerName,
          signatureJson: result.toJson(),
        );
      } else {
        await repository.saveReporterSignature(
        reportId: reportId, signerName: result.signerName,
        signatureJson: result.toJson(),
      );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(SkoLanguageController.tr('報告者サインを保存しました'))),
      );
      await _loadSelectedSite();
      widget.onRegistrationSaved?.call();
    } catch (error) {
      _rememberManagementHold(error);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(SkoLanguageController.trParams('報告者サインを保存できませんでした: {error}', {'error': dailyReportActionErrorMessage(error),
              }),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _sign() async {
    if (_managementHold || _saving) return;
    if (_report?.reporterSignatureJson == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('先に作業内容を保存し、報告者サインを登録してください。')));
      return;
    }
    FocusScope.of(context).unfocus();
    if (!_visitReport && _editSessionUnverified) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(SkoLanguageController.tr('編集申請の状態を確認できません。日報を再読み込みしてください。'))));
      return;
    }
    final signingActor = _repository?.currentActorId;
    final signingDate = _date;
    final signingSite = _siteId;
    final signingRoute = _routeAssignmentId;
    void checkSigningContext() {
      if (signingActor == null ||
          _repository?.currentActorId != signingActor ||
          _date != signingDate ||
          _siteId != signingSite ||
          _routeAssignmentId != signingRoute) {
        throw const DailyReportActorChanged();
      }
    }

    setState(() => _saving = true);
    try {
      final reportId = await _saveBeforeSignature();
      if (reportId == null || !mounted) return;
      checkSigningContext();
      var sharedBefore = await _readSharedContext(reportId: reportId);
      if (!mounted) return;
      checkSigningContext();
      if (sharedBefore?.isManagementHold == true) return;
      if (sharedBefore?.explicitFinalizationRequired == true && sharedBefore?.reporterSaved == true &&
          sharedBefore?.supervisorSaved != true) {
        final before = sharedBefore!;
        final prepared = await _sharedReportRepository!.prepareProvisionalFacts(before: before,
          workers: [for (final worker in _workers) {...worker.toRpcJson(),
            'confirmed_hours': _enteredConfirmedHours(worker.workerId),
            'confirmation_reason': worker.workerId == before.workerId || _managementFactsReason.text.trim().isEmpty
              ? null : _managementFactsReason.text.trim()}]);
        if (!mounted) return;
        checkSigningContext();
        _verifySharedContext(prepared, reportId: reportId);
        sharedBefore = prepared;
        _sharedContext = prepared;
      }
      if (sharedBefore?.explicitFinalizationRequired == true && !sharedBefore!.supervisorReady) {
        await _confirmPendingFactsBeforeSupervisor(sharedBefore, checkSigningContext);
        sharedBefore = await _readSharedContext(reportId: reportId);
        if (!mounted) return;
        checkSigningContext();
      }
      if (sharedBefore?.enabled == true && !sharedBefore!.supervisorReady) {
        await _reviewSupervisorFacts(sharedBefore);
        return;
      }
      if (sharedBefore?.documentOnly != true) {
        await _checkPaidHoursBeforeSignature(reportId, checkSigningContext, forSupervisor: true);
      }
      if (!mounted) return;
      checkSigningContext();
      sharedBefore = await _readSharedContext(reportId: reportId);
      if (!mounted) return;
      checkSigningContext();
      if (sharedBefore?.isManagementHold == true) return;
      if (_editingApprovedReport && sharedBefore?.firstReporterCoversWorkOnly == true &&
          sharedBefore?.approvedEditRequestId != _editSession?.requestId) {
        throw StateError('現在の編集申請とサイン対象を確認できません。日報を開き直してください。');
      }
      if (sharedBefore?.documentOnly == true) {
        if (!sharedBefore!.canCollectSupervisor || !_sharedDocumentMatchesEditor(sharedBefore)) {
          throw StateError('サインする日報の内容が変わりました。日報を再読み込みしてください。');
        }
      } else if (sharedBefore?.enabled == true && !await _reviewSupervisorFacts(sharedBefore!)) {
        return;
      }
      if (!mounted) return;
      checkSigningContext();
      // Saving changes invalidates the earlier reporter signature server-side.
      if (_report?.reporterSignatureJson == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(SkoLanguageController.tr('編集内容を保存した場合は、報告者サインを再登録してから確定してください'),
            ),
          ),
        );
        return;
      }
      // Existing saved names take precedence over current registration defaults.
      var responsibleName =
          _report?.responsibleSignerName ?? _report?.signerName ?? '';
      if (responsibleName.trim().isEmpty) {
        try {
          responsibleName = await _repository!.loadResponsibleName(
            siteId: _siteId,
            routeAssignmentId: _visitReport ? null : _routeAssignmentId,
          );
        } on DailyReportActorChanged {
          rethrow;
        } catch (_) {
          // Missing registration or unavailable lookup still allows manual entry.
        }
      }
      if (!mounted) return;
      checkSigningContext();
      final result = await Navigator.of(context).push<SignatureResult>(
        MaterialPageRoute(builder: (_) => SignatureCapturePage(
          initialSignerName: responsibleName,
          title: SkoLanguageController.tr('責任者サイン'),
          signerLabel: SkoLanguageController.tr('現場責任者名'),
          reviewText: sharedBefore?.documentOnly == true ? _documentSignatureSummary(sharedBefore!) : null,
          submitLabel: _editingApprovedReport
              ? SkoLanguageController.tr('このサインを確認') : SkoLanguageController.tr(
                  _explicitFinalizationRequired ? '責任者サインを保存' : '責任者サインで確定'),
        ),
        ),
      );
      if (result == null || !mounted) return;
      checkSigningContext();
      if (_report?.id != reportId) throw StateError('対象日報が変わりました');
      final repository = _repository;
      if (repository == null) return;
      if (_editingApprovedReport) {
        setState(() {
          _pendingResponsibleSignature = result;
          _pendingSharedSignatureContext = sharedBefore?.firstReporterCoversWorkOnly == true
              ? sharedBefore : null;
          _pendingSignatureFingerprint = _draftFingerprint();
          _pendingReporterFingerprint = _signatureFingerprint(_report?.reporterSignatureJson);
        });
        return;
      }
      if (sharedBefore?.enabled == true) {
        final state = await _sharedReportRepository!.collectSupervisor(
          before: sharedBefore!, signerName: result.signerName, signature: {'strokes': result.toJson()});
        _verifySharedContext(state, reportId: reportId);
        if (!state.supervisorSaved) throw StateError('責任者サインの保存を確認できません。再読込してください。');
        _sharedContext = state;
      } else if (_visitReport) {
        await repository.signVisit(
          reportId: reportId,
          role: 'responsible',
          signerName: result.signerName,
          signatureJson: result.toJson(),
        );
      } else {
        await repository.sign(reportId: reportId,
        signerName: result.signerName, signatureJson: result.toJson(),
        );
      }
      if (!mounted) return;
      await _loadSelectedSite();
      if (!mounted) return;
      checkSigningContext();
      final explicitPending = _explicitFinalizationRequired &&
          (_visitReport ? _report?.responsibleSignatureJson != null && !_signed
            : _sharedContext?.supervisorSaved == true && _sharedContext?.explicitFinalizationCompleted != true);
      if (_error != null || !(_signed || _documentComplete || explicitPending) || _report?.id != reportId ||
          _report?.reporterSignatureJson == null || _report?.responsibleSignatureJson == null) {
        throw StateError('責任者サインの保存・確定を再確認できませんでした。日報を再読み込みしてください。再サインは確認後に行ってください。');
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(SkoLanguageController.tr(explicitPending
          ? '責任者サインを保存しました。⑤「保存して確定」で完了します。'
          : _documentComplete ? '責任者サインを保存し、日報が完了しました' : '責任者サインで日報を確定しました'))),
      );
      widget.onRegistrationSaved?.call();
      if (mounted && _error == null && shouldFinishCheckoutReport(
        signed: _signed || _documentComplete,
        isVisitReport: _visitReport,
        reportRouteId: _routeAssignmentId,
        checkoutRouteId: widget.initialRouteAssignmentId,
        checkoutSourceId: widget.groupClockInAnchorId,
        reportDate: _date,
        checkoutDate: widget.initialDate,
      )) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      _rememberManagementHold(error);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(SkoLanguageController.trParams('確定できませんでした: {error}', {'error': dailyReportActionErrorMessage(error),
              }),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _finalizeVisitReport() async {
    final repository = _repository;
    final before = _report;
    final visit = widget.routeVisitContext;
    final actor = repository?.currentActorId;
    if (_saving || repository == null || before == null || visit == null || actor == null ||
        !before.canFinalizeVisit) { return; }
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      await repository.finalizeVisit(context: visit, before: before);
      if (!mounted || repository.currentActorId != actor) throw const DailyReportActorChanged();
      await _loadSelectedSite();
      if (!mounted || repository.currentActorId != actor) throw const DailyReportActorChanged();
      if (_error != null || _report?.id != before.id || !_signed || _report?.visitFinalizationCompleted != true) {
        throw StateError('現場訪問日報の確定を再確認できません。再読み込みしてください。');
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('現場訪問の日報を保存して確定しました。')));
      widget.onRegistrationSaved?.call();
    } catch (error) {
      if (mounted && repository.currentActorId == actor) { await _loadSelectedSite(); }
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(dailyReportActionErrorMessage(error)))); }
    } finally { if (mounted) setState(() => _saving = false); }
  }

  Future<void> _startVisitFinalizationEdit() async {
    final repository = _repository;
    final before = _report;
    final visit = widget.routeVisitContext;
    final actor = repository?.currentActorId;
    if (_saving || repository == null || before == null || visit == null || actor == null ||
        !before.canEditVisitDraft) { return; }
    final accepted = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
      title: const Text('日報を手直し'),
      content: const Text('現在の日報とサインは履歴に残します。手直し後は報告者と責任者のサインを取り直します。'),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('戻る')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('手直しを始める'))]));
    if (accepted != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await repository.startVisitFinalizationEdit(context: visit, before: before, reason: '現場メンバーが確定前の訪問日報を手直し');
      if (!mounted || repository.currentActorId != actor) throw const DailyReportActorChanged();
      await _loadSelectedSite();
      if (!mounted || repository.currentActorId != actor) throw const DailyReportActorChanged();
      if (_error != null || _report?.id != before.id || _report?.reporterSignatureJson != null ||
          _report?.responsibleSignatureJson != null || _report?.status != 'draft') {
        throw StateError('手直しの開始を再確認できません。日報を開き直してください。');
      }
    } catch (error) {
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(dailyReportActionErrorMessage(error)))); }
    } finally { if (mounted) setState(() => _saving = false); }
  }

  Future<void> _finalizeReport() async {
    final repository = _sharedReportRepository;
    final before = _sharedContext;
    if (_saving || _managementHold || repository == null || before == null ||
        !before.canFinalize || before.reportId != _report?.id ||
        before.actorId != _repository?.currentActorId) { return; }
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      final after = await repository.finalize(before: before);
      if (!mounted) return;
      _verifySharedContext(after, reportId: before.reportId);
      _sharedContext = after;
      await _loadSelectedSite();
      if (!mounted) return;
      if (_error != null || _sharedContext?.explicitFinalizationCompleted != true ||
          _report?.id != before.reportId || !_signed ||
          _repository?.currentActorId != before.actorId) {
        throw StateError('日報の確定と給与・請求への反映を再確認できません。日報を開き直してください。');
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('保存して確定しました。')));
      widget.onRegistrationSaved?.call();
    } catch (error) {
      // A lost acknowledgement may already have committed. Reload the server
      // state before allowing another explicit attempt; never write again here.
      if (mounted && _repository?.currentActorId == before.actorId) {
        await _loadSelectedSite();
      }
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(dailyReportActionErrorMessage(error)))); }
    } finally { if (mounted) setState(() => _saving = false); }
  }

  Future<void> _beginApprovedEdit() async {
    if (_managementHold) return;
    final repository = _repository;
    final report = _report;
    final actor = repository?.currentActorId;
    if (_saving || _visitReport || repository == null || report == null ||
        !report.signed || !_approvedEditAvailable || actor == null) {
      return;
    }
    setState(() => _saving = true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('承認済みの編集を開始'),
          content: Text(SkoLanguageController.tr('編集を開始すると以前のサインを解除します。編集後に報告者と責任者の再サインが必要です。')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(SkoLanguageController.tr('キャンセル'))),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(SkoLanguageController.tr('編集を開始'))),
          ],
        ),
      );
      if (confirmed != true || !mounted || repository.currentActorId != actor) {
        return;
      }
      if (!await repository.hasApprovedEdit(report.id) ||
          repository.currentActorId != actor || !mounted ||
          _report?.id != report.id) {
        throw StateError('承認済みの編集申請を確認できません。再読み込みしてください。');
      }
      final session = await repository.approvedEditSession(report);
      if (session == null || repository.currentActorId != actor || !mounted) {
        throw StateError('編集申請の識別情報を確認できません');
      }
      await _editSessions.remember(session);
      if (repository.currentActorId != actor || !mounted) {
        throw const DailyReportActorChanged();
      }
      // This RPC consumes only the current actor's approved request and clears
      // obsolete signatures in the same existing transaction.
      final id = await _saveDraft(ownsBusyState: false, approvedReset: session);
      if (!mounted || repository.currentActorId != actor) return;
      if (id != report.id || _report?.id != report.id || _signed ||
          _report?.reporterSignatureJson != null ||
          _report?.responsibleSignatureJson != null) {
        throw StateError('編集開始を確認できません。日報を再読み込みしてください。');
      }
      if (!await repository.verifyEditSession(session) ||
          repository.currentActorId != actor || !mounted) {
        throw StateError('編集申請の使用済み状態を確認できません');
      }
      await _editSessions.remember(session.confirm());
      if (!mounted || repository.currentActorId != actor) {
        throw const DailyReportActorChanged();
      }
      setState(() {
        _editSession = session.confirm();
        _editSessionUnverified = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
        SkoLanguageController.tr('編集できる状態になりました。編集後は報告者・責任者のサインを登録してください。'),
      )));
    } catch (error) {
      if (mounted && repository.currentActorId == actor) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('編集を開始できませんでした: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _signatureFingerprint(Object? signature) => jsonEncode(
    SignatureResult(signerName: '', strokes: SignatureResult.fromJson(signature),
      canvasSize: SignatureResult.sizeFromJson(signature)).toJson());

  String _recordContentFingerprint(DailyReportRecord report) {
    final workers = report.workers.toList()
      ..sort((a, b) => a.workerId.compareTo(b.workerId));
    return jsonEncode({'description': report.workDescription.trim(),
      'workers': workers.map((worker) => worker.toRpcJson()).toList()});
  }

  Future<void> _finishApprovedEdit() async {
    final repository = _repository;
    final session = _editSession;
    final signature = _pendingResponsibleSignature;
    final report = _report;
    if (_managementHold || _saving || !_editingApprovedReport || repository == null ||
        session == null || signature == null || report == null) {
      return;
    }
    final actor = session.actorId;
    void checkContext() {
      if (!mounted || repository.currentActorId != actor ||
          _report?.id != session.reportId || _editSession?.requestId != session.requestId) {
        throw const DailyReportActorChanged();
      }
    }
    setState(() => _saving = true);
    try {
      checkContext();
      if (_pendingSignatureFingerprint != _draftFingerprint() ||
          _savedDraftFingerprint != _draftFingerprint() ||
          _pendingReporterFingerprint != _signatureFingerprint(report.reporterSignatureJson)) {
        _invalidatePendingSignature();
        throw StateError('内容が変更されています。報告者・責任者のサインを確認してください。');
      }
      if (!await repository.verifyEditSession(session)) {
        throw StateError('編集申請を確認できません');
      }
      checkContext();
      Future<DailyReportRecord> reloadExact() async {
        final row = await repository.loadReport(date: report.date,
          siteId: report.siteId, routeAssignmentId: report.routeAssignmentId,
          reportId: session.reportId);
        checkContext();
        if (row == null || row.id != session.reportId ||
            row.companyId != session.companyId) {
          throw StateError('対象日報を確認できません');
        }
        return row;
      }
      bool matchesSignature(DailyReportRecord row) =>
        (row.signed || (_sharedContext?.explicitFinalizationRequired == true && row.status == 'draft')) &&
        row.responsibleSignerName?.trim() == signature.signerName.trim() &&
        _signatureFingerprint(row.responsibleSignatureJson) ==
          _signatureFingerprint({'strokes': signature.toJson()}) &&
        _signatureFingerprint(row.reporterSignatureJson) == _pendingReporterFingerprint;
      var latest = await reloadExact();
      // A lost response may have committed. Read before retry; never submit
      // another signature when the exact final state is already present.
      if (!matchesSignature(latest)) {
        if (latest.status != 'draft' || latest.responsibleSignatureJson != null ||
            _recordContentFingerprint(latest) != _recordContentFingerprint(report) ||
            _signatureFingerprint(latest.reporterSignatureJson) != _pendingReporterFingerprint) {
          throw StateError('日報またはサインが変更されています。再読み込みしてください。');
        }
        final captured = _pendingSharedSignatureContext;
        if (_sharedContext?.firstReporterCoversWorkOnly == true || captured != null) {
          if (captured == null || captured.reportId != session.reportId ||
              captured.actorId != session.actorId || captured.approvedEditRequestId != session.requestId ||
              !captured.canCollectSupervisor || _sharedReportRepository == null) {
            throw StateError('編集申請と確認済みのサイン内容を再確認してください。');
          }
          final saved = await _sharedReportRepository.collectApprovedSupervisor(
            before: captured, requestId: session.requestId, signerName: signature.signerName,
            signature: {'strokes': signature.toJson()});
          checkContext();
          _verifySharedContext(saved, reportId: session.reportId);
          if (!saved.supervisorSaved) throw StateError('編集後の責任者サインを確認できません。');
          _sharedContext = saved;
        } else {
          await repository.sign(reportId: session.reportId,
            signerName: signature.signerName, signatureJson: signature.toJson());
        }
        checkContext();
        latest = await reloadExact();
        if (!matchesSignature(latest)) {
          throw StateError('編集完了を確認できません。同じ画面で再確認してください。');
        }
      }
      if (_sharedContext?.explicitFinalizationRequired == true && !latest.signed) {
        final sharedRepository = _sharedReportRepository;
        if (sharedRepository == null || !matchesSignature(latest) ||
            _recordContentFingerprint(latest) != _recordContentFingerprint(report)) {
          throw StateError('保存する編集内容とサインを確認できません。');
        }
        final before = await sharedRepository.loadReport(session.reportId, expectedActor: actor);
        checkContext();
        _verifySharedContext(before, reportId: session.reportId);
        final finalized = await sharedRepository.finalize(before: before);
        checkContext();
        _verifySharedContext(finalized, reportId: session.reportId);
        _sharedContext = finalized;
        latest = await reloadExact();
        if (!latest.signed || !matchesSignature(latest)) {
          throw StateError('編集した日報の確定を再確認できません。同じ画面で再確認してください。');
        }
      }
      checkContext();
      await _editSessions.clear(session);
      checkContext();
      setState(() {
        _report = latest;
        _editSession = null;
        _pendingResponsibleSignature = null;
        _pendingSharedSignatureContext = null;
      });
      if (!mounted) return;
      await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (completionContext) => Scaffold(
          appBar: AppBar(title: Text(SkoLanguageController.tr('編集完了')), automaticallyImplyLeading: false),
          body: Center(child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.check_circle, size: 72, color: Colors.green),
              const SizedBox(height: 16),
              Text(SkoLanguageController.tr('日報の編集を完了しました。保存して確定しました。')),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.of(completionContext).popUntil((route) => route.isFirst),
                child: Text(SkoLanguageController.tr('ホームへ戻る')),
              ),
            ]),
          )),
        ),
      ));
    } catch (error) {
      _rememberManagementHold(error);
      if (mounted && repository.currentActorId == actor) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('編集完了を確認できませんでした。サインを保持しています: $error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  bool _sharedDocumentMatchesEditor(SharedDailyReportContext state) {
    if (!_sharedWorkMatchesEditor(state)) return false;
    final rows = state.documentBasis?['workers'];
    if (rows is! List || rows.length != _workers.length) return false;
    for (final worker in _workers) {
      final matches = rows.where((row) => row is Map && row['worker_id'] == worker.workerId).toList();
      if (matches.length != 1) return false;
      final row = matches.single as Map;
      if (row['worker_name'] != worker.workerName ||
          row['overtime_hours'] != worker.overtimeHours || row['early_hours'] != worker.earlyHours ||
          row['night_hours'] != worker.nightHours || row['allowance_amount'] != worker.allowanceAmount ||
          (row['allowance_label'] ?? '') != worker.allowanceLabel ||
          row['vehicle_id'] != worker.vehicleId || row['route_assignment_id'] != worker.routeId ||
          row['odometer_km'] != worker.odometerKm) { return false; }
      final savedChoices = row['company_allowance_selections'];
      final shownChoices = worker.companyAllowanceSelections;
      if ((savedChoices == null) != (shownChoices == null)) return false;
      if (savedChoices != null && jsonEncode(DailyReportCompanyAllowanceSelections.fromJson(savedChoices).toJson()) !=
          jsonEncode(shownChoices!.toJson())) { return false; }
    }
    return true;
  }

  String _documentSignatureSummary(SharedDailyReportContext state) {
    final lines = <String>['サインする日報', state.workDescription,
      '勤務日：${state.workDate.toIso8601String().substring(0, 10)}'];
    for (final row in state.documentBasis!['workers'] as List) {
      lines.add('${row['worker_name']}：残業 ${row['overtime_hours']}h / 早出 ${row['early_hours']}h / 夜間 ${row['night_hours']}h');
      final label = row['allowance_label'];
      if (label is String && label.isNotEmpty) lines.add('手当：$label');
      if (row['odometer_km'] != null) lines.add('走行距離：${row['odometer_km']}km');
    }
    return lines.join('\n');
  }

  String _preparedFinancialReportId() {
    final state = _sharedContext;
    // A reload must retain this marker. Never send staged rows through the old
    // draft writer, which omits category and can invalidate the actual facts.
    _applyControllers();
    if (state == null || !state.financialTransitionPending || !state.financialTransitionValid ||
        state.reportId != _report?.id || state.actorId != _repository?.currentActorId ||
        _savedDraftFingerprint != _draftFingerprint()) {
      throw StateError('確認済み勤務実績と日報が一致しません。保存せず、日報を開き直してください。');
    }
    return state.reportId!;
  }

  Future<void> _prepareFinancialResigning() async {
    final repository = _sharedReportRepository;
    final initial = _sharedContext;
    final factsRepository = _workerFactsRepository;
    if (_saving || factsRepository == null || repository == null || initial == null || initial.reportId == null ||
        !initial.canManageAttendance || !initial.documentOnly) { return; }
    setState(() => _saving = true);
    try {
      var current = await repository.loadReport(initial.reportId!, expectedActor: initial.actorId);
      if (!mounted) return;
      if (!current.financialResigningSupported || !current.canManageAttendance || !current.documentOnly ||
          current.reportId != initial.reportId || current.companyId != initial.companyId) {
        throw StateError('勤務実績の連携は準備中です。現在のサインは変更していません。');
      }
      if (current.reporterSaved || current.supervisorSaved) {
        final accepted = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
          title: const Text('勤務実績を確認して再サイン'),
          content: const Text('現在の日報とサインを履歴に残し、今回のサインを解除します。実際の勤務区分・適用手当・必要な時間を確認した後、報告者と現場責任者に改めてサインしてもらいます。'),
          actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('戻る')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('履歴に残して確認を始める'))]));
        if (accepted != true || !mounted) return;
        current = await repository.startDocumentEdit(before: current,
          reason: '管理者が実際の勤務実績と適用手当を確認し、報告者・現場責任者のサインを取り直す');
      }
      if (!mounted) return;
      if (current.reporterSaved || current.supervisorSaved || !current.financialResigningSupported) {
        throw StateError('勤務実績を確認する状態を再読み込みしてください。');
      }
      _invalidatePendingSignature();
      await _loadSelectedSite();
      if (!mounted) return;
      final before = _sharedContext;
      if (before == null || before.reportId != current.reportId || before.actorId != current.actorId ||
          !before.documentOnly || before.reporterSaved || before.supervisorSaved ||
          !before.financialResigningSupported || _error != null) {
        throw StateError('手直しを始めた日報を再確認できません。日報を開き直してください。');
      }
      final prepared = await Navigator.of(context).push<SharedDailyReportContext>(MaterialPageRoute(
        builder: (_) => _FinancialResigningReviewPage(
          before: before, reportRepository: repository, factsRepository: factsRepository,
          workers: _workers, companyAllowanceItems: _repository?.currentActorId == _companyAllowanceActor
            ? _companyAllowanceItems : const [],
          companyAllowanceEligibility: _repository?.currentActorId == _companyAllowanceActor
            ? _companyAllowanceEligibility : const {},
          companyAllowanceNamesLoading: _companyAllowanceNamesLoading,
          companyAllowanceNamesUnavailable: _companyAllowanceNamesUnavailable)));
      if (!mounted) return;
      await _loadSelectedSite();
      if (!mounted || prepared == null) return;
      if (_sharedContext?.financialTransitionId != prepared.financialTransitionId ||
          _sharedContext?.financialTransitionValid != true || _report?.reporterSignatureJson != null ||
          _report?.responsibleSignatureJson != null || _error != null) {
        throw StateError('保存済み勤務実績を再確認できません。再読み込みしてください。');
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('勤務実績を保存しました。報告者、現場責任者の順に新しいサインをもらってください。')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(dailyReportActionErrorMessage(error))));
    } finally { if (mounted) setState(() => _saving = false); }
  }

  Future<void> _startDocumentEdit() async {
    final repository = _sharedReportRepository;
    final before = _sharedContext;
    if (_saving || repository == null || before == null || !(before.documentEditable || before.explicitFinalizationEditable) || before.reportId != _report?.id) return;
    final accepted = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
      title: const Text('日報を手直し'),
      content: const Text('現在の日報とサインは履歴に残します。手直し後は報告者と責任者のサインを取り直します。'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('戻る')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('手直しを始める')),
      ]));
    if (accepted != true || !mounted) return;
    setState(() => _saving = true);
    try {
      if (_sharedContext != before || _repository?.currentActorId != before.actorId) throw const DailyReportActorChanged();
      if (before.explicitFinalizationRequired) {
        await repository.startFinalizationEdit(before: before, reason: '現場メンバーが確定前の日報を手直し');
      } else {
        await repository.startDocumentEdit(before: before, reason: '本人が日報の手直しを開始');
      }
      if (!mounted) return;
      if (_repository?.currentActorId != before.actorId) throw const DailyReportActorChanged();
      _invalidatePendingSignature();
      await _loadSelectedSite();
      if (!mounted) return;
      if (_error != null || _report?.id != before.reportId || _report?.reporterSignatureJson != null ||
          _report?.responsibleSignatureJson != null ||
          (before.explicitFinalizationRequired
            ? _sharedContext?.explicitFinalizationRequired != true : _sharedContext?.documentOnly != true)) {
        throw StateError('手直しを開始した状態を再確認できません。日報を開き直してください。');
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('日報を手直しできます。保存後にサインを取り直してください。')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(dailyReportActionErrorMessage(error))));
    } finally { if (mounted) setState(() => _saving = false); }
  }

  Future<void> _requestEdit() async {
    if (_saving) return;
    final report = _report;
    final repository = _repository;
    if (report == null || repository == null) return;

    final reason = TextEditingController();
    setState(() => _saving = true);
    try {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(SkoLanguageController.tr('確定済み日報を修正')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              SkoLanguageController.tr('確定済みの日報は直接変更できません。会社で設定した承認担当者（1〜3名）へ承認依頼を送ります。',
                ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reason,
              maxLines: 3,
              decoration: InputDecoration(labelText: SkoLanguageController.tr('修正理由（任意）'),
                ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(SkoLanguageController.tr('キャンセル')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(SkoLanguageController.tr('承認依頼を送る')),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
      await repository.requestEdit(
        reportId: report.id,
        reason: reason.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            SkoLanguageController.tr('承認依頼を送りました。設定された承認担当者の承認後、日報を開いて編集できます。'),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(SkoLanguageController.trParams('承認依頼を送れませんでした: {error}', {'error': error,
            }),
          ),
        ),
      );
    } finally {
      reason.dispose();
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showSignature() async {
    final report = _report;
    if (report == null) return;
    final signature =
        report.responsibleSignatureJson ?? report.signatureJson;
    if (signature == null) return;
    final strokes = SignatureResult.fromJson(signature);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          SkoLanguageController.trParams('責任者サイン：{name}', {'name': report.responsibleSignerName ?? report.signerName ?? '',
          }),
        ),
        content: SizedBox(
          width: 460,
          child: SignaturePreview(strokes: strokes, height: 220, canvasSize: SignatureResult.sizeFromJson(signature)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(SkoLanguageController.tr('閉じる')),
          ),
        ],
      ),
    );
  }

  static const _helpText = '①作業内容を入力します（必須）。②メンバー別の勤務区分と、該当する早出・残業・手当を確認します。勤務区分は会社の判定設定と実際の出勤記録から初期入力し、必要時は修正できます。会社設定がない場合は勤務区分を選んでください。早出・残業・手当は該当なしなら飛ばせます。時間単位の給与・手当がある場合は、休憩を除いた実勤務時間を入力してください。打刻の差から実勤務時間を推測しません。\n\n③報告者本人がサインすると自動で仮保存します。作業内容と報告者サインの保存に成功するまでは日報の作成を続けます。通信が失敗しても退勤し直さず、保存状態を再確認してください。仮保存に成功したら他の画面へ移動でき、アプリを閉じた後も保存済みの日報から再開できます。\n\n④当日その現場に出勤した対象メンバーなら誰でも、仮保存の日報を開き、責任者本人にサインしてもらえます。報告者サインからそのまま続けても、後から取得してもかまいません。⑤「保存して確定」を押して初めて確定し、「確定済み」と表示します。サインを保存しただけでは⑤の完了ではありません。\n\n給与・請求への反映は、最終退勤の日報の⑤が成功したときに一度だけ行います。途中現場の日報も①〜⑤で確定しますが、その現場の文書の確定です。途中現場の日報だけでは給与・請求に反映せず、最終退勤の日報で反映します。確定済みの給与・請求書は勝手に書き換えません。設定不足などで反映できない場合は成功扱いにせず、画面の案内に従って確認してください。\n\n一人の現場は退勤後そのまま日報へ進みます。複数人なら「日報を作成する／退勤のみ」を選びます。最初に退勤した人を自動で日報担当にはしません。全員が退勤のみでも日報未作成を残し、後から対象メンバーが作成できます。同じ勤務の日報を重複して作成しません。\n\n②の「手当を選ぶ」から、会社に登録された適用可能な手当を選びます。手当名や単価の入力し直しは不要です。月単位の手当は個別給料設定で確認します。選択は登録IDと版を付けて保存し、保存済みの名称や調整額を自動で置き換えません。任意の「入力途中を保存」は確定ではなく、報告者サインの代わりにもなりません。\n\n確定前の作業内容・早出・残業・手当を変える場合は「手直し」から進みます。以前の日報とサインは履歴に残し、変更後の内容へ必要なサインを取り直します。古いサインを変更後の承認に流用しません。確定後の修正には正規の編集承認を使います。管理者の勤怠管理では権限を確認したうえで編集・削除・サイン登録ができ、変更履歴を残します。管理者が本人に代わって勤務実績を確認するときは理由が必要です。\n\n勤怠・現場記録は下部の参照情報です。保存済み写真を見る操作は日報の手順の番号には含めません。日報件数は面表紙のある日報だけを数え、写真ページは数えません。GPSの退勤確認通知は自動退勤ではなく、本人の退勤操作が必要です。';

  void _showHelp() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(SkoLanguageController.tr('日報の使い方')),
      content: SingleChildScrollView(child: Text(SkoLanguageController.tr(_helpText))),
      actions: [TextButton(onPressed: () => Navigator.pop(context),
        child: Text(SkoLanguageController.tr('閉じる')))],
    ),
  );

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    return PopScope(
      canPop: !_registrationNavigationLocked,
      child: Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !_registrationNavigationLocked,
        title: Text(
          SkoLanguageController.tr('日報'),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(onPressed: _saving ? null : _showHelp,
            icon: const Icon(Icons.help_outline), tooltip: SkoLanguageController.tr('ヘルプ')),
          if (!_registrationNavigationLocked) TextButton.icon(
            key: const Key('daily-report-month-list'),
            label: Text(SkoLanguageController.tr('保存済み一覧')),
            onPressed: _saving ? null : () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => DailyReportMonthPage(initialMonth: _date),
                    ),
            ),
            icon: const Icon(Icons.list_alt_outlined),
          ),
          if (!_registrationNavigationLocked) const SkoNotificationBell(),
        ],
      ),
      bottomNavigationBar: _notificationRetryReportId == null &&
          !(widget.restrictedReporterRegistration && widget.onManageRegistration != null &&
            _sharedContext?.canManageAttendance == true) ? null : SafeArea(
        child: Padding(padding: const EdgeInsets.all(12), child: Column(
          mainAxisSize: MainAxisSize.min, children: [
            if (widget.restrictedReporterRegistration && widget.onManageRegistration != null &&
                _sharedContext?.canManageAttendance == true)
              OutlinedButton.icon(key: const ValueKey('daily-report-management-recovery'),
                onPressed: _saving ? null : widget.onManageRegistration,
                icon: const Icon(Icons.manage_accounts_outlined),
                label: const Text('管理者の勤怠管理で確認')),
            if (_notificationRetryReportId != null) OutlinedButton.icon(
              onPressed: _saving ? null : _retrySavedReportNotification,
              icon: const Icon(Icons.notifications_outlined),
              label: Text(SkoLanguageController.tr('登録済み日報の通知のみ再確認'))),
          ])),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _ErrorState(message: _error!, onRetry: _loadDay)
                : _groups.isEmpty
                    ? _EmptyDay(date: _date, onPickDate: _pickDate)
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
                        children: [
                          _HeaderField(
                            icon: Icons.calendar_today_outlined,
                            label: SkoLanguageController.tr('日付'),
                            value:
                                '${_date.year}/${_two(_date.month)}/${_two(_date.day)}',
                            onTap: _saving || widget.restrictedReporterRegistration || _visitReport || widget.initialReportId != null ? null : _pickDate,
                          ),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<String>(
                            initialValue: _groups
                                .where(
                                  (g) =>
                                      g.siteId == _siteId &&
                                      g.routeAssignmentId ==
                                          _routeAssignmentId,
                                )
                                .map((g) => g.destinationKey)
                                .firstOrNull,
                            decoration: InputDecoration(
                              labelText: SkoLanguageController.tr('現場／ルート'),
                              prefixIcon: Icon(Icons.route_outlined),
                            ),
                            items: [
                              for (final group in _groups)
                                DropdownMenuItem(
                                  value: group.destinationKey,
                                  child: Text(
                                    group.routeAssignmentId == null
                                        ? group.siteName
                                        : SkoLanguageController.trParams('ルート：{name}', {'name': group.siteName,
                                  }),
                                  ),
                                ),
                            ],
                            onChanged: _saving || widget.restrictedReporterRegistration || _visitReport || widget.initialReportId != null ? null : _selectSite,
                          ),
                          const SizedBox(height: 16),
                          _MemberSummary(workers: _workers),
                          if (_managementHold) Card(child: ListTile(
                            leading: const Icon(Icons.pause_circle_outline),
                            title: const Text('勤怠管理での確認が必要です'),
                            subtitle: Text(_managementHoldMessage))),
                          if (_sharedFactsReadOnly && !_managementHold)
                            Card(child: ExpansionTile(
                              leading: const Icon(Icons.group_outlined),
                              title: Text(SkoLanguageController.trParams('{name}さんが日報を登録しました',
                                {'name': _sharedContext!.reporterName})),
                              children: [Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                child: Text(SkoLanguageController.tr(
                                  _sharedContext?.explicitFinalizationRequired == true
                                    ? '報告者サインまで仮保存済みです。他の画面へ移動できます。当日の現場メンバーが責任者本人のサインをもらい、⑤「保存して確定」で完了します。確定前の変更は「手直し」から行います。'
                                    : 'この日報の内容と報告者サインは保存済みです。重複登録は不要です。責任者本人のサインは対象メンバーが取得できます。内容の変更には編集承認が必要です。')))],
                            )),
                          DailyReportPendingNotice(
                            hasClockedInWorkers: _groups.any((group) =>
                              group.siteId == _siteId &&
                              group.routeAssignmentId == _routeAssignmentId &&
                              group.workers.isNotEmpty,
                    ),
                            isSigned: _signed || _documentComplete,
                          ),
                          const SizedBox(height: 16),
                          if (widget.vehicleClockInId != null)
                            VehicleDriverMeterEntry(
                              sourceClockInId: widget.vehicleClockInId!,
                              expectedSiteId: _siteId,
                              expectedRouteId: _routeAssignmentId,
                              requireDestinationMatch: true,
                              expectedWorkDate: '${_date.year.toString().padLeft(4, '0')}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
                            ),
                          Card(child: ExpansionTile(
                            leading: const Icon(Icons.help_outline),
                            title: const Text('入力の流れ・サインの説明'),
                            children: [Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              child: Text('① 作業内容（必須）\n② 早出・残業・手当（該当なしなら飛ばせます）\n③ 報告者サインで自動仮保存\n④ 責任者本人がサイン\n⑤ 保存して確定\n仮保存後は他の画面へ移動できます。${_visitReport ? 'この現場の日報を確定します。給与・請求は最終退勤の日報で反映します。' : '給与・請求への反映は⑤の成功後です。'}'))],
                          )),
                          const SizedBox(height: 8),
                          TextField(
                            key: const ValueKey('daily-report-work-description'),
                            controller: _workDescription,
                            enabled: _editable,
                            minLines: 6,
                            maxLines: 12,
                            decoration: InputDecoration(
                              labelText: SkoLanguageController.tr('作業内容'),
                              prefixIcon: const _ReportStepBadge('①'),
                              alignLabelWithHint: true,
                              hintText: SkoLanguageController.tr('本日の作業内容を入力'),
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (!_sharedFactsReadOnly || _sharedContext?.explicitFinalizationRequired == true) Row(children: [
                            _ReportStepBadge(_dailyStep(2)),
                            const SizedBox(width: 8),
                            Expanded(child: Text(
                              SkoLanguageController.tr('メンバー別 残業・早出・手当'),
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            )),
                          ]),
                          const SizedBox(height: 8),
                          if (!_sharedFactsReadOnly || _sharedContext?.explicitFinalizationRequired == true) for (final worker in _workers) ...[
                            _WorkerDetailCard(
                              worker: worker,
                              editable: _editable,
                              expandOptionalFields: _preparedAllowanceWorkerId == worker.workerId,
                              allowanceFieldKey: _allowanceFieldKeys.putIfAbsent(worker.workerId, GlobalKey.new),
                              onPrepareAllowances: !_visitReport && _report?.id.isNotEmpty != true
                                ? () => _prepareCompanyAllowanceChoices(worker.workerId) : null,
                              confirmedHours: _sharedContext?.explicitFinalizationRequired == true ? _confirmedHours[worker.workerId] : null,
                              confirmedHoursEditable: !_saving && !_signed && _sharedContext?.supervisorSaved != true &&
                                  (_sharedContext?.reporterSaved != true || _sharedContext?.workerId == worker.workerId ||
                                    _sharedContext?.canManageAttendance == true ||
                                    _sharedContext?.explicitFinalizationRequired == true),
                              onWorkCategoryChanged: (value) {
                                _invalidatePendingSignature();
                                setState(() => worker.workCategory = value);
                              },
                              companyAllowanceItems:
                                  _repository?.currentActorId == _companyAllowanceActor
                                      ? _companyAllowanceItems : const [],
                              companyAllowanceSelectionMode: !_visitReport,
                              eligibleCompanyAllowanceKeys: _repository?.currentActorId == _companyAllowanceActor
                                  ? _companyAllowanceEligibility[worker.workerId] : null,
                              needsSavedAllowanceReport: _report?.id.isNotEmpty != true,
                              onCompanyAllowanceSelections: (selected) {
                                _invalidatePendingSignature();
                                setState(() => worker.companyAllowanceSelections = selected);
                              },
                              companyAllowanceNamesLoading: _companyAllowanceNamesLoading,
                              companyAllowanceNamesUnavailable: _companyAllowanceNamesUnavailable,
                              overtime: _overtime[worker.workerId]!,
                              early: _early[worker.workerId]!,
                              night: _night[worker.workerId]!,
                              allowanceLabel:
                                  _allowanceLabel[worker.workerId]!,
                              odometer: _odometer[worker.workerId]!,
                              onCaptureOdometer: () =>
                                  _captureOdometer(worker),
                            ),
                            const SizedBox(height: 8),
                          ],
                          const SizedBox(height: 8),
                          if (!_managementHold && !_visitReport && _sharedContext?.explicitFinalizationRequired != true && _sharedContext?.enabled == true &&
                              _sharedContext?.firstReporterCoversWorkOnly == true &&
                              _sharedContext?.reporterSaved == true &&
                              _report?.companyId != null && _workerFactsRepository != null)
                            Builder(builder: (context) {
                              final section = _WorkerFactsConfirmationSection(
                              repository: _workerFactsRepository,
                              independentSignature: _sharedContext?.documentOnly == true,
                              readOnly: _sharedContext?.financialTransitionPending == true,
                              companyId: _report!.companyId!, reportId: _report!.id,
                              workers: _workers, sourceRevision: _report,
                              companyAllowanceItems: _repository?.currentActorId == _companyAllowanceActor
                                  ? _companyAllowanceItems : const [],
                              companyAllowanceEligibility: _repository?.currentActorId == _companyAllowanceActor
                                  ? _companyAllowanceEligibility : const {},
                              companyAllowanceNamesLoading: _companyAllowanceNamesLoading,
                              companyAllowanceNamesUnavailable: _companyAllowanceNamesUnavailable,
                              onSaved: () => unawaited(_afterPaidHoursSaved()),
                            );
                              return _sharedContext?.documentOnly == true
                                  ? _DeferredDocumentFacts(
                                      key: ValueKey('document-facts/${_repository?.currentActorId}/${_report!.id}'),
                                      child: section)
                                  : section;
                            }),
                          if (!_managementHold && !_visitReport && _sharedContext?.firstReporterCoversWorkOnly != true && _report?.id.isNotEmpty == true &&
                              _report?.companyId != null && _paidHoursRepository != null)
                            PaidWorkHoursReportSection(
                              repository: _paidHoursRepository,
                              companyId: _report!.companyId!, reportId: _report!.id,
                              workerNames: {for (final worker in _workers) worker.workerId: worker.workerName},
                              sourceRevision: _report,
                              onSaved: () => unawaited(_afterPaidHoursSaved()),
                            ),
                          if (_sharedContext?.explicitFinalizationRequired == true &&
                              _sharedContext?.canManageAttendance == true &&
                              _sharedContext!.hoursAnnexInputs.any((input) =>
                                input['worker_id'] != _sharedContext?.workerId && input['confirmed'] != true))
                            Padding(padding: const EdgeInsets.only(bottom: 12), child: TextField(
                              key: const ValueKey('daily-report-management-facts-reason'),
                              controller: _managementFactsReason, enabled: !_saving && !_signed,
                              decoration: const InputDecoration(labelText: '本人に代わって勤務実績を確認する理由'))),
                          Card(
                            child: ListTile(
                              leading: _ReportStepBadge(_dailyStep(3)),
                              title: Text(
                                SkoLanguageController.tr('報告者サイン'),
                                style: TextStyle(fontWeight: FontWeight.w900),
                              ),
                              subtitle: _report?.reporterSignatureJson == null ? null : Text(
                                _report?.reporterSignerName ?? SkoLanguageController.tr('報告者サイン済み')),
                              trailing: _managementHold || _signed || _visitReporterLocked || _sharedFactsReadOnly
                                  ? null
                                  : const Icon(Icons.chevron_right),
                              onTap: _managementHold || _saving || _signed || _visitReporterLocked || _sharedFactsReadOnly ? null : _signReporter,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (_signed || _documentComplete || _sharedContext?.supervisorSaved == true ||
                              (_visitReport && _report?.responsibleSignatureJson != null))
                            Card(
                              child: ListTile(
                                leading: _ReportStepBadge(_dailyStep(4)),
                                title: Text(
                                  SkoLanguageController.tr(_explicitFinalizationRequired
                                      ? '責任者サイン済み' : _documentComplete ? '責任者サイン済み・日報完了' : '責任者サイン済み・確定'),
                                  style: TextStyle(fontWeight: FontWeight.w900),
                                ),
                                subtitle: Text(
                                  _report?.responsibleSignerName ?? _report?.signerName ?? SkoLanguageController.tr('責任者サイン済み'),
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: _showSignature,
                              ),
                            )
                          else
                            Card(
                              child: ListTile(
                                leading: _ReportStepBadge(_dailyStep(4)),
                                title: Text(
                                  SkoLanguageController.tr('責任者サイン'),
                                  style: TextStyle(fontWeight: FontWeight.w900),
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: _managementHold || _saving || (widget.restrictedReporterRegistration &&
                                    _sharedContext?.canAccessSupervisorCollection != true) ? null : _sign,
                              ),
                            ),
                          const SizedBox(height: 16),
                          if (!_editingApprovedReport) Card(child: Padding(padding: const EdgeInsets.all(16),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              Row(children: [const _ReportStepBadge('⑤'), const SizedBox(width: 8),
                                Expanded(child: Text(_signed ? '確定済み' : '保存して確定',
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)))]),
                              const SizedBox(height: 8),
                              if (!_signed) FilledButton.icon(
                                key: const ValueKey('daily-report-finalize'),
                                onPressed: _saving || _managementHold || (_visitReport
                                    ? _report?.canFinalizeVisit != true : _sharedContext?.canFinalize != true)
                                  ? null : _visitReport ? _finalizeVisitReport : _finalizeReport,
                                icon: const Icon(Icons.check_circle_outline),
                                label: const Text('保存して確定')),
                              if (!_signed) Text(_explicitFinalizationRequired
                                ? (_visitReport ? '現場訪問の日報を保存して確定します。給与・請求は、退勤後の日報を確定したときに反映します。'
                                  : '報告者・責任者のサインと勤務実績がそろったら保存できます。成功後に給与・請求へ反映されます。')
                                : '日報の確定処理は準備中です。管理者に確認してください。'),
                            ]))),
                          const SizedBox(height: 16),
                          if (_editingApprovedReport && !_signed)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Column(children: [
                                Text(_pendingResponsibleSignature == null
                                  ? SkoLanguageController.tr('編集後に報告者・責任者のサインを登録し、「編集を完了」を押してください。画面を開き直した場合は責任者サインを再入力してください。')
                                   : SkoLanguageController.tr('責任者サインを確認しました。「編集を完了」で保存・確定します。')),
                                FilledButton.icon(
                                  key: const ValueKey('daily-report-finish-approved-edit'),
                                  onPressed: _saving || _pendingResponsibleSignature == null
                                    ? null : _finishApprovedEdit,
                                  icon: const Icon(Icons.check_circle_outline),
                                  label: Text(SkoLanguageController.tr(_sharedContext?.explicitFinalizationRequired == true
                                    ? '⑤ 保存して確定' : '編集を完了')),
                                ),
                              ]),
                            ),
                          if (!_managementHold && !_signed && !_visitReporterLocked && !_sharedFactsReadOnly && _sharedContext?.financialTransitionPending != true)
                            TextButton.icon(
                              key: const ValueKey('daily-report-save-draft'),
                              onPressed: _saving ? null : _register,
                              icon: const Icon(Icons.save_outlined),
                              label: const Text('入力途中を保存'),
                            ),
                          if (_report?.canEditVisitDraft == true || _sharedContext?.explicitFinalizationEditable == true ||
                              (_sharedContext?.documentOnly == true && _sharedContext?.documentEditable == true))
                            OutlinedButton.icon(
                              key: const ValueKey('daily-report-start-document-edit'),
                              onPressed: _saving ? null : _visitReport ? _startVisitFinalizationEdit : _startDocumentEdit,
                              icon: const Icon(Icons.edit_outlined), label: const Text('手直し')),
                          if (_sharedContext?.documentOnly == true && _sharedContext?.canManageAttendance == true)
                            OutlinedButton.icon(key: const ValueKey('daily-report-financial-resigning'),
                              onPressed: _saving ? null : _prepareFinancialResigning,
                              icon: const Icon(Icons.fact_check_outlined),
                              label: const Text('勤務実績を確認して給与・請求へ進む')),
                          if (_sharedContext?.financialTransitionPending == true)
                            Text(_sharedContext?.financialTransitionValid == true
                              ? (_sharedContext?.reporterSaved == true
                                ? '報告者の新しいサインは保存済みです。現場責任者のサインをもらってください。'
                                : '勤務実績は保存済みです。報告者と現場責任者の新しいサインをもらってください。')
                              : '確認済み勤務実績の状態を確認できません。サインせず管理者に確認してください。'),
                          if (_documentComplete)
                            const Padding(padding: EdgeInsets.symmetric(vertical: 8),
                              child: Text('日報のサインは保存済みです。給与・請求への反映には、勤務実績の確認と新しいサインが必要です。')),
                          if (_signed && !_visitReport && _approvedEditAvailable)
                            FilledButton.icon(
                              key: const ValueKey('daily-report-begin-approved-edit'),
                              onPressed: _managementHold || _saving ? null : _beginApprovedEdit,
                              icon: const Icon(Icons.edit_outlined),
                              label: Text(SkoLanguageController.tr('承認済みの編集を開始')),
                            ),
                          if (_signed && !_visitReport && !_approvedEditAvailable)
                            FilledButton.tonalIcon(
                              onPressed: _saving ? null : _requestEdit,
                              icon: const Icon(Icons.edit_outlined),
                              label: Text(SkoLanguageController.tr('編集・修正を申請')),
                    ),
                  if (_signed && _visitReport)
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: Text(SkoLanguageController.tr('次の現場へ')),
                            ),
                          const SizedBox(height: 10),
                          if (_evidence.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Card(
                              child: ListTile(
                                leading: const Icon(Icons.photo_library_outlined),
                                title: Text(
                                  SkoLanguageController.tr('勤怠・現場記録'),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900),
                                ),
                                subtitle: Text(
                                  SkoLanguageController.trParams('{count}件 / この日報に紐付いています', {'count': _evidence.length},
                          ),
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: _registrationNavigationLocked ? null : () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => DailyReportEvidencePage(
                                      date: _date,
                                      siteName: _siteName ?? '',
                                      items: _evidence,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                          OutlinedButton.icon(
                            onPressed: _registrationNavigationLocked ? null : () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => DailyReportPrintPreviewPage(
                                  date: _date,
                                  siteName: _siteName ?? '',
                                  workers: _workers,
                                  workDescription: _workDescription.text,
                                  report: _report,
                                  evidence: _evidence,
                                ),
                              ),
                            ),
                            icon: const Icon(Icons.print_outlined),
                            label: Text(SkoLanguageController.tr('A4印刷プレビュー')),
                          ),
                        ],
                      ),
      ),
    ));
  }

  static String _number(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}

class _DeferredDocumentFacts extends StatefulWidget {
  const _DeferredDocumentFacts({super.key, required this.child});
  final Widget child;
  @override State<_DeferredDocumentFacts> createState() => _DeferredDocumentFactsState();
}
class _DeferredDocumentFactsState extends State<_DeferredDocumentFacts> {
  bool _opened = false;
  @override Widget build(BuildContext context) => Card(child: ExpansionTile(
    maintainState: true,
    title: const Text('勤務実績・手当（給与・請求への反映は別途確認）'),
    onExpansionChanged: (expanded) { if (expanded && !_opened) setState(() => _opened = true); },
    children: _opened ? [widget.child] : const <Widget>[],
  ));
}

class _FinancialResigningReviewPage extends StatefulWidget {
  const _FinancialResigningReviewPage({required this.before, required this.reportRepository,
    required this.factsRepository, required this.workers, required this.companyAllowanceItems,
    required this.companyAllowanceEligibility, required this.companyAllowanceNamesLoading,
    required this.companyAllowanceNamesUnavailable});
  final SharedDailyReportContext before;
  final SharedDailyReportRepository reportRepository;
  final SharedWorkerFactsRepository factsRepository;
  final List<DailyReportWorkerDraft> workers;
  final List<CompanyAllowanceLabel> companyAllowanceItems;
  final Map<String, Set<String>> companyAllowanceEligibility;
  final bool companyAllowanceNamesLoading, companyAllowanceNamesUnavailable;
  @override State<_FinancialResigningReviewPage> createState() => _FinancialResigningReviewPageState();
}
class _FinancialResigningReviewPageState extends State<_FinancialResigningReviewPage> {
  final _reason = TextEditingController();
  final _inputs = <String, SharedWorkerFactsTransitionInput>{};
  late Future<List<SharedWorkerFactsSnapshot>> _future;
  bool _saving = false;
  String? _error;
  @override void initState() { super.initState(); _future = _load(); }
  Future<List<SharedWorkerFactsSnapshot>> _load() => Future.wait([
    for (final worker in widget.workers) widget.factsRepository.load(
      companyId: widget.before.companyId, reportId: widget.before.reportId!, workerId: worker.workerId),
  ]);
  void _reload() => setState(() { _inputs.clear(); _error = null; _future = _load(); });
  Future<void> _save() async {
    if (_saving || _inputs.length != widget.workers.length) { return; }
    setState(() { _saving = true; _error = null; });
    try {
      final after = await widget.reportRepository.prepareFinancialResigning(before: widget.before,
        workers: [for (final worker in widget.workers) _inputs[worker.workerId]!], reason: _reason.text);
      if (mounted) Navigator.of(context).pop(after);
    } catch (error) {
      if (mounted) setState(() => _error = dailyReportActionErrorMessage(error));
    } finally { if (mounted) setState(() => _saving = false); }
  }
  @override void dispose() { _reason.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Scaffold(appBar: AppBar(title: const Text('勤務実績を確認して再サイン')),
      body: FutureBuilder<List<SharedWorkerFactsSnapshot>>(future: _future, builder: (context, result) {
        if (result.connectionState != ConnectionState.done) { return const Center(child: CircularProgressIndicator()); }
        if (result.hasError || result.data == null) { return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('勤務原本を確認できません。未確認のまま進めません。'),
          TextButton(onPressed: _reload, child: const Text('再読み込み'))])); }
        return ListView(padding: const EdgeInsets.all(16), children: [
          const Text('① 全員の実際の勤務区分・適用手当・必要な時間を確認してください。\n② 理由を入力して勤務実績を保存します。\n③ 元の日報で報告者と現場責任者の新しいサインをもらいます。'),
          const Text('古いサインは履歴に残っています。勤務区分を推測したり、選択済み手当を自動で消すことはありません。車両・既存調整額はこの手順では変更できません。'),
          for (final snapshot in result.data!) _WorkerFactsConfirmationCard(
            key: ValueKey('financial-review/${snapshot.actorId}/${snapshot.reportId}/${snapshot.workerId}/${snapshot.revision}/${snapshot.scopeFingerprint}'),
            repository: widget.factsRepository, snapshot: snapshot,
            template: widget.workers.singleWhere((worker) => worker.workerId == snapshot.workerId),
            companyAllowanceItems: widget.companyAllowanceItems,
            eligibleCompanyAllowanceKeys: widget.companyAllowanceEligibility[snapshot.workerId],
            companyAllowanceNamesLoading: widget.companyAllowanceNamesLoading,
            companyAllowanceNamesUnavailable: widget.companyAllowanceNamesUnavailable,
            readOnly: _saving,
            stageInput: (input) => setState(() => _inputs[snapshot.workerId] = input),
            onInputChanged: () => setState(() => _inputs.remove(snapshot.workerId)),
            onSaved: () {}, onReload: _reload),
          Text('${_inputs.length} / ${widget.workers.length} 人の内容を確認済み'),
          TextField(key: const ValueKey('financial-transition-reason'), controller: _reason,
            enabled: !_saving, maxLength: 1000, minLines: 2, maxLines: 4,
            decoration: const InputDecoration(labelText: '管理者が実績を確認・手直しする理由（必須）')),
          if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          FilledButton.icon(key: const ValueKey('prepare-financial-resigning'),
            onPressed: _saving || _inputs.length != widget.workers.length ? null : _save,
            icon: const Icon(Icons.fact_check_outlined),
            label: Text(_saving ? '保存中…' : '確認した勤務実績を保存してサインへ')),
        ]);
      })));
}

class _WorkerFactsConfirmationSection extends StatefulWidget {
  const _WorkerFactsConfirmationSection({this.readOnly = false, required this.repository,
    required this.companyId, required this.reportId, required this.workers,
    required this.sourceRevision, required this.companyAllowanceItems,
    required this.companyAllowanceEligibility, required this.companyAllowanceNamesLoading,
    required this.companyAllowanceNamesUnavailable, required this.onSaved,
    this.independentSignature = false});
  final SharedWorkerFactsRepository repository;
  final bool independentSignature, readOnly;
  final String companyId, reportId;
  final List<DailyReportWorkerDraft> workers;
  final Object? sourceRevision;
  final List<CompanyAllowanceLabel> companyAllowanceItems;
  final Map<String, Set<String>> companyAllowanceEligibility;
  final bool companyAllowanceNamesLoading, companyAllowanceNamesUnavailable;
  final VoidCallback onSaved;
  @override State<_WorkerFactsConfirmationSection> createState() => _WorkerFactsConfirmationSectionState();
}
class _WorkerFactsConfirmationSectionState extends State<_WorkerFactsConfirmationSection> {
  late Future<List<SharedWorkerFactsSnapshot>> _future;
  @override void initState() { super.initState(); _future = _load(); }
  Future<List<SharedWorkerFactsSnapshot>> _load() => Future.wait([
    for (final worker in widget.workers) widget.repository.load(companyId: widget.companyId,
      reportId: widget.reportId, workerId: worker.workerId),
  ]);
  @override void didUpdateWidget(_WorkerFactsConfirmationSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reportId != widget.reportId || oldWidget.companyId != widget.companyId ||
        oldWidget.workers.map((worker) => worker.workerId).join(',') != widget.workers.map((worker) => worker.workerId).join(',') ||
        !identical(oldWidget.sourceRevision, widget.sourceRevision)) { _future = _load(); }
  }
  void _reload() => setState(() => _future = _load());
  @override Widget build(BuildContext context) => FutureBuilder<List<SharedWorkerFactsSnapshot>>(
    future: _future, builder: (context, result) {
      if (result.connectionState != ConnectionState.done) { return const LinearProgressIndicator(); }
      if (result.hasError || result.data == null) { return Card(child: ListTile(
        title: const Text('本人の勤務実績を確認できません。'),
        subtitle: const Text('未確認を0として扱わず、再読み込みしてください。'),
        trailing: TextButton(onPressed: _reload, child: const Text('再読込')))); }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('本人の勤務実績を確認',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
        Text(widget.independentSignature
          ? '勤務実績・手当の確認は日報のサインと別に行います。未確認を0とせず、本人が内容を確認して保存してください。'
          : '作業報告のサインとは別に、各自の退勤後の実績を確認します。本人の確認・必要な時間がそろってから、責任者本人にサインしてもらいます。'),
        for (final snapshot in result.data!) _WorkerFactsConfirmationCard(
          key: ValueKey('facts/${snapshot.actorId}/${snapshot.reportId}/${snapshot.workerId}'),
          repository: widget.repository, snapshot: snapshot, readOnly: widget.readOnly,
          template: widget.workers.singleWhere((worker) => worker.workerId == snapshot.workerId),
          companyAllowanceItems: widget.companyAllowanceItems,
          eligibleCompanyAllowanceKeys: widget.companyAllowanceEligibility[snapshot.workerId],
          companyAllowanceNamesLoading: widget.companyAllowanceNamesLoading,
          companyAllowanceNamesUnavailable: widget.companyAllowanceNamesUnavailable,
          onSaved: widget.onSaved, onReload: _reload),
      ]);
    });
}

class _WorkerFactsConfirmationCard extends StatefulWidget {
  const _WorkerFactsConfirmationCard({super.key, required this.repository,
    required this.snapshot, required this.template, required this.companyAllowanceItems,
    required this.eligibleCompanyAllowanceKeys, required this.companyAllowanceNamesLoading,
    required this.companyAllowanceNamesUnavailable, required this.onSaved, required this.onReload,
    this.stageInput, this.onInputChanged, this.readOnly = false});
  final SharedWorkerFactsRepository repository;
  final SharedWorkerFactsSnapshot snapshot;
  final DailyReportWorkerDraft template;
  final List<CompanyAllowanceLabel> companyAllowanceItems;
  final Set<String>? eligibleCompanyAllowanceKeys;
  final bool companyAllowanceNamesLoading, companyAllowanceNamesUnavailable;
  final VoidCallback onSaved, onReload;
  final ValueChanged<SharedWorkerFactsTransitionInput>? stageInput;
  final VoidCallback? onInputChanged;
  final bool readOnly;
  @override State<_WorkerFactsConfirmationCard> createState() => _WorkerFactsConfirmationCardState();
}
class _WorkerFactsConfirmationCardState extends State<_WorkerFactsConfirmationCard> {
  final _overtime = TextEditingController(), _early = TextEditingController(),
      _night = TextEditingController(), _allowance = TextEditingController(),
      _odometer = TextEditingController(), _hours = TextEditingController(),
      _reason = TextEditingController();
  DailyReportWorkerDraft? _draft;
  String? _category, _error;
  bool _saving = false, _staged = false, _seeding = false;
  bool get _staging => widget.stageInput != null;
  SharedWorkerFactsSnapshot get _snapshot => widget.snapshot;
  bool get _managed => !_snapshot.isOwnWorker && _snapshot.canManageAttendance;
  bool get _editable => !widget.readOnly && !_saving && !_snapshot.sourceBlocked &&
      (_staging ? _snapshot.canManageAttendance : _snapshot.scope.workReportFrozen &&
        !_snapshot.scope.supervisorFinalized && (_snapshot.editable || _managed));
  bool get _requiresHours => _snapshot.hoursRequiredOutsideCurrentReport ||
      _draft?.companyAllowanceSelections?.items.any((item) => item.unit == 'hour') == true;
  String _number(double value) => value == value.roundToDouble() ? value.toInt().toString() : value.toString();
  @override void initState() {
    super.initState(); _seed();
    for (final controller in [_overtime, _early, _night, _allowance, _odometer, _hours]) {
      controller.addListener(_inputChanged);
    }
  }
  void _inputChanged() {
    if (!_staging || _seeding) return;
    _staged = false; widget.onInputChanged?.call();
  }
  void _seed() {
    _seeding = true; _staged = false;
    final seed = _snapshot.current ? _snapshot.facts : _snapshot.proposedFacts;
    final template = widget.template;
    // A missing server proposal can mean an unset work category. Keep the
    // saved report values as unconfirmed input; never invent a category or
    // bypass the server's source, permission, revision or validation checks.
    _draft = seed?.toDraft(workerId: _snapshot.workerId,
      workerName: template.workerName, template: template) ??
      DailyReportWorkerDraft(workerId: template.workerId, workerName: template.workerName,
        overtimeHours: template.overtimeHours, earlyHours: template.earlyHours,
        nightHours: template.nightHours, workCategory: template.workCategory, allowanceAmount: template.allowanceAmount,
        allowanceLabel: template.allowanceLabel,
        companyAllowanceSelections: template.companyAllowanceSelections,
        vehicleId: template.vehicleId, vehicleName: template.vehicleName,
        routeId: template.routeId, routeName: template.routeName, odometerKm: template.odometerKm,
        sourceClockInId: template.sourceClockInId, sourceClockOutAt: template.sourceClockOutAt,
        meterManaged: template.meterManaged, meterEventId: template.meterEventId,
        meterSourceClockInId: template.meterSourceClockInId,
        previousOdometerKm: template.previousOdometerKm, tripDistanceKm: template.tripDistanceKm);
    _category = seed?.workCategory ?? template.workCategory;
    _overtime.text = _number(_draft!.overtimeHours);
    _early.text = _number(_draft!.earlyHours);
    _night.text = _number(_draft!.nightHours);
    _allowance.text = _draft!.allowanceLabel;
    final odometer = _draft!.odometerKm;
    _odometer.text = odometer == null ? '' : _number(odometer);
    _hours.text = !_snapshot.current || _snapshot.hours == null ? '' : _number(_snapshot.hours!);
    _reason.clear();
    _error = null; _seeding = false;
  }
  @override void didUpdateWidget(_WorkerFactsConfirmationCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.snapshot.actorId != _snapshot.actorId ||
        oldWidget.snapshot.revision != _snapshot.revision ||
        oldWidget.snapshot.scopeFingerprint != _snapshot.scopeFingerprint ||
        oldWidget.snapshot.workBasisHash != _snapshot.workBasisHash ||
        oldWidget.snapshot.current != _snapshot.current) { _seed(); }
  }
  double _readNumber(TextEditingController controller, String label) {
    final text = controller.text.trim();
    if (!RegExp(r'^(?:0|[1-9]\d?)(?:\.\d{1,4})?$').hasMatch(text)) {
      throw FormatException('$labelを0〜24の数値で入力してください。');
    }
    final value = double.parse(text);
    if (!value.isFinite || value > 24) throw FormatException('$labelを0〜24の数値で入力してください。');
    return value;
  }
  Future<void> _confirm() async {
    final draft = _draft;
    if (!_editable || draft == null) return;
    if (_category == null) {
      setState(() => _error = '勤務区分（日勤・夜勤など）を選んでください。');
      return;
    }
    final before = _snapshot;
    setState(() { _saving = true; _error = null; });
    try {
      draft.overtimeHours = _readNumber(_overtime, '残業時間');
      draft.earlyHours = _readNumber(_early, '早出時間');
      draft.nightHours = _readNumber(_night, '夜間時間');
      draft.allowanceLabel = _allowance.text.trim();
      if (draft.vehicleId != null && !draft.meterManaged) {
        final raw = _odometer.text.trim();
        final value = double.tryParse(raw);
        if (value == null || !value.isFinite || value < 0) throw const FormatException('走行距離を確認してください。');
        draft.odometerKm = value;
      }
      final hours = _requiresHours ? _readNumber(_hours, '実勤務時間') : null;
      if (!_staging && _managed && _reason.text.trim().isEmpty) throw const FormatException('管理者が確認する理由を入力してください。');
      final choices = draft.companyAllowanceSelections?.items ?? const <DailyReportCompanyAllowanceSelection>[];
      final allowed = widget.eligibleCompanyAllowanceKeys;
      if (choices.isNotEmpty && (widget.companyAllowanceNamesLoading || widget.companyAllowanceNamesUnavailable || allowed == null)) {
        throw StateError('会社手当の適用対象を確認できません。再読み込みしてください。');
      }
      final unavailable = choices.where((item) => !allowed!.contains(item.key)).toList();
      if (unavailable.isNotEmpty) {
        throw StateError('保存済みの「${unavailable.map((item) => item.nameSnapshot).join('、')}」は現在の給与区分に適用できません。手当の選択を見直してください。');
      }
      final facts = SharedWorkerFacts.fromDraft(draft, workCategory: _category!);
      if (_staging) {
        widget.stageInput!(SharedWorkerFactsTransitionInput(before: before, facts: facts, hours: hours));
        if (mounted) setState(() => _staged = true);
        return;
      }
      final saved = await widget.repository.confirm(before, facts, hours: hours,
        managementReason: _managed ? _reason.text.trim() : null);
      if (!mounted) return;
      if (saved.actorId != before.actorId || saved.reportId != before.reportId ||
          saved.workerId != before.workerId || !saved.confirmed || !saved.current) {
        throw StateError('勤務実績の確認結果を取得できません。再読み込みしてください。');
      }
      widget.onSaved();
    } catch (error) {
      if (mounted) setState(() => _error = dailyReportActionErrorMessage(error));
    } finally { if (mounted) setState(() => _saving = false); }
  }
  @override void dispose() {
    for (final controller in [_overtime, _early, _night, _allowance, _odometer, _hours, _reason]) { controller.dispose(); }
    super.dispose();
  }
  @override Widget build(BuildContext context) {
    final draft = _draft;
    return Card(child: ExpansionTile(
      initiallyExpanded: _snapshot.isOwnWorker && (!_snapshot.confirmed || !_snapshot.current),
      leading: Icon(_snapshot.confirmed && _snapshot.current ? Icons.verified_outlined : Icons.pending_actions_outlined),
      title: Text(widget.template.workerName),
      subtitle: Text(_snapshot.confirmed && _snapshot.current ? '勤務実績を確認済み' :
        _snapshot.sourceBlocked ? '退勤原本の確認が必要です' : '本人の勤務実績は未確認です'),
      childrenPadding: const EdgeInsets.all(12), children: [
        if (!_snapshot.confirmed || !_snapshot.current)
          const Text('表示は未確認の入力候補です。0の項目も含めて内容を確認し、確認ボタンで保存してください。'),
        if (_snapshot.sourceBlocked) const Text('本人の退勤と勤務原本を確認してから、実績を保存してください。'),
        if (!_staging && !_snapshot.scope.workReportFrozen) const Text('作業報告の報告者サインを保存してから、本人の勤務実績を確認します。'),
        if (_snapshot.proposedFacts == null && !_snapshot.current)
          const Text('入力候補を作成できなかったため、保存済み日報の値を表示しています。勤務区分を選び、各項目を確認して保存してください。'),
        if (draft == null) TextButton(onPressed: widget.onReload, child: const Text('入力候補を再読み込み'))
        else ...[
          DropdownButtonFormField<String>(
            key: ValueKey('facts-category/${_snapshot.workerId}/${_snapshot.revision}/${_snapshot.scopeFingerprint}'),
            initialValue: _category, decoration: const InputDecoration(labelText: '勤務区分'),
            items: const [DropdownMenuItem(value: 'day', child: Text('日勤')),
              DropdownMenuItem(value: 'night', child: Text('夜勤')),
              DropdownMenuItem(value: 'holiday', child: Text('休日勤務')),
              DropdownMenuItem(value: 'holiday_night', child: Text('休日夜勤'))],
            onChanged: _editable ? (value) => setState(() { _category = value; _inputChanged(); }) : null),
          const SizedBox(height: 10),
          if (draft.allowanceAmount != 0) Text('既存の調整額：${draft.allowanceAmount}円（この画面では変更しません）'),
          _WorkerDetailCard(worker: draft, editable: _editable, inlineFields: true, allowOdometerCamera: false,
            allowVehicleEdits: !_staging,
            companyAllowanceItems: widget.companyAllowanceItems, companyAllowanceSelectionMode: true,
            eligibleCompanyAllowanceKeys: widget.eligibleCompanyAllowanceKeys, needsSavedAllowanceReport: false,
            onCompanyAllowanceSelections: (value) => setState(() { draft.companyAllowanceSelections = value; _inputChanged(); }),
            companyAllowanceNamesLoading: widget.companyAllowanceNamesLoading,
            companyAllowanceNamesUnavailable: widget.companyAllowanceNamesUnavailable,
            overtime: _overtime, early: _early, night: _night, allowanceLabel: _allowance,
            odometer: _odometer, onCaptureOdometer: () {}),
          if (_requiresHours) Padding(padding: const EdgeInsets.only(top: 10), child: TextField(
            controller: _hours, enabled: _editable,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: '実勤務時間（休憩を除く）', suffixText: '時間',
              helperText: '出退勤の差から推測せず、実際に働いた時間を確認します。'))),
          if (!_staging && _managed) TextField(controller: _reason, enabled: _editable,
            decoration: const InputDecoration(labelText: '管理者が本人に代わって確認する理由')),
          if (_error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(_error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error))),
          if (_editable || _saving) FilledButton.icon(
            key: ValueKey('confirm-worker-facts/${_snapshot.workerId}'),
            onPressed: _saving ? null : _confirm,
            icon: const Icon(Icons.fact_check_outlined),
            label: Text(_saving ? '保存中…' : _staging ? (_staged ? 'この内容を確認済み' : 'この人の勤務実績を確認') : _managed ? '理由を記録して勤務実績を確認' : 'この勤務実績を確認して保存')),
        ],
      ]));
  }
}

class _WorkerDetailCard extends StatelessWidget {
  const _WorkerDetailCard({
    required this.worker,
    required this.editable,
    required this.companyAllowanceItems,
    required this.companyAllowanceSelectionMode,
    required this.eligibleCompanyAllowanceKeys,
    required this.needsSavedAllowanceReport,
    required this.onCompanyAllowanceSelections,
    required this.companyAllowanceNamesLoading,
    required this.companyAllowanceNamesUnavailable,
    required this.overtime,
    required this.early,
    required this.night,
    required this.allowanceLabel,
    required this.odometer,
    required this.onCaptureOdometer,
    this.inlineFields = false,
    this.onWorkCategoryChanged, this.confirmedHours, this.confirmedHoursEditable = false,
    this.expandOptionalFields = false, this.allowanceFieldKey, this.onPrepareAllowances,
    this.allowOdometerCamera = true, this.allowVehicleEdits = true,
  });

  final DailyReportWorkerDraft worker;
  final bool editable;
  final List<CompanyAllowanceLabel> companyAllowanceItems;
  final bool companyAllowanceSelectionMode;
  final Set<String>? eligibleCompanyAllowanceKeys;
  final bool needsSavedAllowanceReport;
  final ValueChanged<DailyReportCompanyAllowanceSelections> onCompanyAllowanceSelections;
  final bool companyAllowanceNamesLoading, companyAllowanceNamesUnavailable;
  final TextEditingController overtime;
  final TextEditingController early;
  final TextEditingController night;
  final TextEditingController allowanceLabel;
  final TextEditingController odometer;
  final VoidCallback onCaptureOdometer;
  final bool inlineFields, allowOdometerCamera, allowVehicleEdits;
  final ValueChanged<String?>? onWorkCategoryChanged;
  final TextEditingController? confirmedHours;
  final bool confirmedHoursEditable, expandOptionalFields;
  final GlobalKey? allowanceFieldKey;
  final VoidCallback? onPrepareAllowances;

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    if (inlineFields) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _fields(context));
    return Card(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (onWorkCategoryChanged != null) Padding(padding: const EdgeInsets.all(14),
        child: DropdownButtonFormField<String>(
          key: ValueKey('daily-report-category/${worker.workerId}/${worker.workCategory}'),
          initialValue: worker.workCategory,
          decoration: InputDecoration(labelText: '${worker.workerName}の勤務区分（必須）',
            helperText: worker.workCategory == null ? '勤務区分を選んでください' : null),
          items: const [DropdownMenuItem(value: 'day', child: Text('日勤')),
            DropdownMenuItem(value: 'night', child: Text('夜勤')),
            DropdownMenuItem(value: 'holiday', child: Text('休日勤務')),
            DropdownMenuItem(value: 'holiday_night', child: Text('休日夜勤'))],
          onChanged: editable ? onWorkCategoryChanged : null)),
      if (confirmedHours != null) Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        child: TextField(key: ValueKey('daily-report-confirmed-hours/${worker.workerId}'),
          controller: confirmedHours, enabled: confirmedHoursEditable,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: '実勤務時間（時間単位の給与・手当がある場合）',
            suffixText: '時間', helperText: '休憩を除いた実際の時間を入力します。該当なしなら空欄で進めます。'))),
      ExpansionTile(
        key: ValueKey('worker-details/${worker.workerId}/$expandOptionalFields'),
        initiallyExpanded: expandOptionalFields,
        leading: const CircleAvatar(child: Icon(Icons.person_outline)),
        title: Text(
          worker.workerName,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Text(
          [
            SkoLanguageController.tr('個別の残業・早出・手当を設定'),
            if (worker.sourceClockInId != null)
              SkoLanguageController.tr(worker.sourceClockOutAt == null
                ? '退勤未登録・確定前に確認' : '退勤済み・元勤務と連携',
              ),
            if (worker.vehicleName?.trim().isNotEmpty == true)
              SkoLanguageController.trParams('車両：{name}', {'name': worker.vehicleName!,
              }),
            if (worker.routeName?.trim().isNotEmpty == true)
              SkoLanguageController.trParams('ルート：{name}', {'name': worker.routeName!,
              }),
          ].join(' / '),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        children: _fields(context),
      ),
    ]));
  }

  List<Widget> _fields(BuildContext context) => [
          if (worker.vehicleName?.trim().isNotEmpty == true ||
              worker.routeName?.trim().isNotEmpty == true) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                [
                  if (worker.vehicleName?.trim().isNotEmpty == true)
                    SkoLanguageController.trParams('車両：{name}', {'name': worker.vehicleName!,
                    }),
                  if (worker.routeName?.trim().isNotEmpty == true)
                    SkoLanguageController.trParams('ルート：{name}', {'name': worker.routeName!,
                    }),
                ].join('　'),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (worker.meterManaged) ...[
            Text(SkoLanguageController.tr(worker.meterEventId == null
              ? '運転手のメーター登録待ち' : '車両距離は運転手の登録記録から表示します',
              ),
            ),
            if (worker.previousOdometerKm != null)
              Text('${SkoLanguageController.tr('前回距離')}: ${worker.previousOdometerKm} km',
              ),
            if (worker.meterEventId != null && worker.odometerKm != null)
              Text('${SkoLanguageController.tr('今回距離')}: ${worker.odometerKm} km',
              ),
            if (worker.tripDistanceKm != null)
              Text('${SkoLanguageController.tr('当日の走行距離')}: ${worker.tripDistanceKm} km',
              ),
            const SizedBox(height: 10),
          ],
          if (worker.vehicleId != null && !worker.meterManaged) ...[
            TextField(
              controller: odometer,
              enabled: editable && allowVehicleEdits,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true,
              ),
              decoration: InputDecoration(
                labelText: SkoLanguageController.tr('退勤時の走行距離'),
                suffixText: 'km',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            if (allowOdometerCamera) SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: editable ? onCaptureOdometer : null,
                icon: const Icon(Icons.camera_alt_outlined),
                label: Text(SkoLanguageController.tr('メーターを撮影して読取')),
              ),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Expanded(
                child: _NumberField(
                  controller: overtime,
                  label: SkoLanguageController.tr('残業(h)'),
                  enabled: editable,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _NumberField(
                  controller: early,
                  label: SkoLanguageController.tr('早出(h)'),
                  enabled: editable,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _NumberField(
                  controller: night,
                  label: SkoLanguageController.tr('夜間(h)'),
                  enabled: editable,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (companyAllowanceSelectionMode && needsSavedAllowanceReport && onPrepareAllowances != null)
            OutlinedButton.icon(key: ValueKey('prepare-allowances/${worker.workerId}'),
              onPressed: editable ? onPrepareAllowances : null,
              icon: const Icon(Icons.playlist_add_check), label: const Text('手当を選ぶ'))
          else if (companyAllowanceSelectionMode)
            DailyReportAllowanceNameField(key: allowanceFieldKey, controller: allowanceLabel,
              enabled: editable, registeredItems: companyAllowanceItems,
              eligibleKeys: eligibleCompanyAllowanceKeys, needsSavedReport: needsSavedAllowanceReport,
              selections: worker.companyAllowanceSelections,
              onSelectionsChanged: onCompanyAllowanceSelections,
              loading: companyAllowanceNamesLoading,
              unavailable: companyAllowanceNamesUnavailable)
          else TextField(controller: allowanceLabel, enabled: editable,
            decoration: InputDecoration(labelText: SkoLanguageController.tr('手当名'))),
  ];
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.label,
    required this.enabled,
  });

  final TextEditingController controller;
  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label),
    );
  }
}

class _MemberSummary extends StatelessWidget {
  const _MemberSummary({required this.workers});

  final List<DailyReportWorkerDraft> workers;

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              SkoLanguageController.trParams('朝の出勤メンバー  {count}名', {'count': workers.length,
              }),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final worker in workers)
                  Chip(
                    avatar: const Icon(Icons.person, size: 16),
                    label: Text(worker.workerName),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderField extends StatelessWidget {
  const _HeaderField({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(label),
        subtitle: Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _EmptyDay extends StatelessWidget {
  const _EmptyDay({
    required this.date,
    required this.onPickDate});

  final DateTime date;
  final VoidCallback onPickDate;

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.event_busy_outlined, size: 54),
            const SizedBox(height: 12),
            Text(
              SkoLanguageController.tr('この日の出勤メンバーがまだありません'),
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              SkoLanguageController.tr('朝の出勤登録が行われると、現場とメンバーが日報へ自動表示されます。'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onPickDate,
              icon: const Icon(Icons.calendar_today),
              label: Text(SkoLanguageController.tr('日付を変更')),
            ),
          ],
        ),
      ),
    );
  }
}

class DailyReportEvidencePage extends StatelessWidget {
  const DailyReportEvidencePage({
    super.key,
    required this.date,
    required this.siteName,
    required this.items,
  });

  final DateTime date;
  final String siteName;
  final List<DailyReportEvidenceRecord> items;

  Future<void> _openEvidenceLocation(
    BuildContext context,
    DailyReportEvidenceRecord item,
  ) async {
    if (!item.hasLocation) return;
    final query = '${item.latitude},${item.longitude}';
    final uri = Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': query,
    });
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(SkoLanguageController.tr('位置情報を地図で開けませんでした'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    final repository = DailyReportRepository.maybeCreate();
    return Scaffold(
      appBar: AppBar(
        title: Text(SkoLanguageController.tr('勤怠・現場記録一覧'))),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.calendar_today_outlined),
              title: Text(
                date.year.toString() +
                    '/' +
                    date.month.toString().padLeft(2, '0') +
                    '/' +
                    date.day.toString().padLeft(2, '0'),
              ),
              subtitle: Text(siteName),
            ),
          ),
          const SizedBox(height: 8),
          for (final item in items)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      item.workerName +
                          ' / ' +
                          SkoLanguageController.tr(item.eventLabel),
                      style: const TextStyle(
                        fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.confirmedAt.hour.toString().padLeft(2, '0') +
                          ':' +
                          item.confirmedAt.minute.toString().padLeft(2, '0'),
                    ),
                    if (item.hasLocation) ...[
                      const SizedBox(height: 6),
                      OutlinedButton.icon(
                        onPressed: () => _openEvidenceLocation(context, item),
                        icon: const Icon(Icons.location_on_outlined),
                        label: Text(
                          item.accuracyM == null
                              ? SkoLanguageController.tr('位置を地図で確認')
                              : SkoLanguageController.trParams('位置を地図で確認（精度 約{accuracy}m）', {'accuracy': item.accuracyM!.round()},
                                ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    if (item.stopLabel != null) Text('${SkoLanguageController.tr('対象現場')}: ${item.stopLabel}',
                      ),
                    if (item.originKind != null) Text(SkoLanguageController.tr(item.originKind == 'company' ? '会社出勤後に現場へ' : '直行直帰',
                        ),
                      ),
                    if (item.photoObservedAt != null) Text('${SkoLanguageController.tr('写真観測時刻')}: ${item.photoObservedAt!.toIso8601String()}',
                      ),
                    if (!item.isTimeOnly && item.photoStatus != null)
                      Text(item.photoCapturedAt == null
                        ? SkoLanguageController.tr(item.eventType == 'route_stop' ? '撮影日時未取得（表示時刻は途中現場の記録時刻）' : '撮影日時未取得（表示時刻は勤怠登録時刻）',
                              )
                        : '${SkoLanguageController.tr('撮影日時')}: ${item.photoCapturedAt!.toIso8601String()}',
                      ),
                    if (!item.isTimeOnly && (item.gpsStatus != null || item.hasLocation) && item.capturedAddress?.trim().isNotEmpty != true)
                      Text(SkoLanguageController.tr('撮影住所未取得')),
                    if (item.capturedAddress?.trim().isNotEmpty == true)
                      Text('${SkoLanguageController.tr('撮影住所')}: ${item.capturedAddress!}',
                      ),
                    if (!item.isTimeOnly && item.photoStatus != null)
                      Text(SkoLanguageController.trParams('写真: {photo} / GPS: {gps}', {
                        'photo': _captureStatusLabel(item.photoStatus),
                        'gps': _captureStatusLabel(item.gpsStatus),
                      },
                        ),
                      ),
                    if (item.storagePath.isEmpty)
                      SizedBox(height: 180,
                        child: Center(child: Text(SkoLanguageController.tr(item.missingPhotoLabel),
                          ),
                        ),
                      ),
                    if (repository != null && item.storagePath.isNotEmpty)
                      FutureBuilder<String>(
                        key: ValueKey('${item.storageBucket}:${item.storagePath}',
                        ),
                        future:
                            repository.attendanceEvidenceUrl(item.storagePath, bucket: item.storageBucket,
                        ),
                        builder: (context, snapshot) {
                          final url = snapshot.data;
                          if (url == null) {
                            return const SizedBox(
                              height: 180,
                              child: Center(
                                child: CircularProgressIndicator()),
                            );
                          }
                          return InteractiveViewer(
                            minScale: 1,
                            maxScale: 5,
                            child: Image.network(
                              url,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) =>
                                  const SizedBox(
                                height: 180,
                                child: Center(
                                  child: Icon(Icons.broken_image_outlined),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class DailyReportPrintPreviewPage extends StatefulWidget {
  const DailyReportPrintPreviewPage({super.key, required this.date,
    required this.siteName, required this.workers, required this.workDescription,
    required this.report, this.evidence = const [], this.resolvedEvidence,
    this.includePhotos = true, this.onEdit, this.onZoomChanged,
  });

  final DateTime date;
  final String siteName;
  final List<DailyReportWorkerDraft> workers;
  final String workDescription;
  final DailyReportRecord? report;
  final List<DailyReportEvidenceRecord> evidence;
  final List<DailyReportPdfEvidence>? resolvedEvidence;
  final bool includePhotos;
  final VoidCallback? onEdit;
  final ValueChanged<bool>? onZoomChanged;

  @override
  State<DailyReportPrintPreviewPage> createState() => _DailyReportPrintPreviewPageState();
}

class _DailyReportPrintPreviewPageState extends State<DailyReportPrintPreviewPage> {
  final _pdfBytes = PdfBytesCache();
  final _photoPdfBytes = PdfBytesCache();
  Future<List<DailyReportPdfEvidence>>? _resolvedEvidence;
  bool _printingPhotos = false;
  String? _fingerprint;

  Future<List<DailyReportPdfEvidence>> _loadEvidence() async {
    if (!widget.includePhotos) return const [];
    if (widget.resolvedEvidence != null) return widget.resolvedEvidence!;
    final repository = DailyReportRepository.maybeCreate();
    if (repository == null) {
      return [for (final record in widget.evidence)
        DailyReportPdfEvidence(record: record, downloadFailed: record.storagePath.isNotEmpty,
          ),
      ];
    }
    return repository.loadPdfEvidence(widget.evidence);
  }

  Future<List<DailyReportPdfEvidence>> _savedEvidence() =>
      _resolvedEvidence ??= _loadEvidence();

  // Keep the LayoutCallback identity stable across zoom state updates. Printing
  // resets its InteractiveViewer mode whenever the callback changes.
  Future<Uint8List> _buildPreviewPdf(PdfPageFormat _) => _pdfBytes.get(() async =>
    DailyReportPdfService.buildPdf(date: widget.date, siteName: widget.siteName,
      workers: widget.workers, workDescription: widget.workDescription,
      report: widget.report, evidence: await _savedEvidence()));

  Future<void> _printReport() async {
    try {
      final bytes = await _pdfBytes.get(() async => DailyReportPdfService.buildPdf(
        date: widget.date, siteName: widget.siteName, workers: widget.workers,
        workDescription: widget.workDescription, report: widget.report,
        evidence: await _savedEvidence()));
      await Printing.layoutPdf(name: '${widget.date.toIso8601String().substring(0, 10)}_日報.pdf',
        format: PdfPageFormat.a4, onLayout: (_) async => bytes);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(SkoLanguageController.tr('日報を印刷できませんでした'))));
      }
    }
  }

  Future<void> _printPhotoPages() async {
    if (_printingPhotos) return;
    setState(() => _printingPhotos = true);
    try {
      final photos = dailyReportPhotoRecords(await _savedEvidence());
      if (photos.isEmpty) return;
      final bytes = await _photoPdfBytes.get(() => DailyReportPdfService.buildPdf(
        date: widget.date, siteName: widget.siteName, workers: widget.workers,
        workDescription: widget.workDescription, report: widget.report,
        evidence: photos, photoPagesOnly: true,
      ),
      );
      await Printing.layoutPdf(
        name: '${widget.date.toIso8601String().substring(0, 10)}_日報写真.pdf',
        format: PdfPageFormat.a4, onLayout: (_) async => bytes,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(SkoLanguageController.tr('写真ページを印刷できませんでした'))),
        );
      }
    } finally {
      if (mounted) setState(() => _printingPhotos = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    final fingerprint = DailyReportPdfService.fingerprint(date: widget.date,
      siteName: widget.siteName, workers: widget.workers,
      workDescription: widget.workDescription, report: widget.report,
      evidence: [for (final record in widget.evidence) DailyReportPdfEvidence(record: record),
      ],
    );
    if (_fingerprint != fingerprint) {
      _fingerprint = fingerprint;
      _pdfBytes.invalidate();
      _photoPdfBytes.invalidate();
      _resolvedEvidence = null;
    }
    return Scaffold(
      appBar: AppBar(title: Text(SkoLanguageController.tr('日報 A4プレビュー')),
        actions: [
          IconButton(tooltip: SkoLanguageController.tr('印刷'),
            onPressed: _printReport, icon: const Icon(Icons.print_outlined)),
          if (widget.onEdit != null) IconButton(tooltip: SkoLanguageController.tr('編集'),
            onPressed: widget.onEdit, icon: const Icon(Icons.edit_outlined)),
          const SkoNotificationBell(),
        ],
      ),
      body: Column(children: [
        if (widget.includePhotos) FutureBuilder<List<DailyReportPdfEvidence>>(
          future: _savedEvidence(),
          builder: (context, snapshot) {
            final photos = dailyReportPhotoRecords(snapshot.data ?? const []);
            return Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6,
                ),
              child: Row(children: [
                Expanded(child: photos.isNotEmpty
                  ? Align(alignment: Alignment.centerLeft,
                      child: DailyReportPhotoPreview(photos: photos),
                            )
                  : Text(SkoLanguageController.tr(snapshot.connectionState == ConnectionState.done
                      ? '写真の記録がありません' : '読込中...',
                              ),
                            ),
                    ),
                TextButton.icon(
                  key: const ValueKey('print-daily-report-photo-pages'),
                  onPressed: photos.isEmpty || _printingPhotos ? null : _printPhotoPages,
                  icon: const Icon(Icons.print_outlined),
                  label: Text(SkoLanguageController.tr('写真ページのみ印刷')),
                ),
              ],
                ),
              );
          },
        ),
        Expanded(child: PdfPreview.builder(initialPageFormat: PdfPageFormat.a4,
          pagesBuilder: (context, pages) => DailyReportZoomPages(pages: pages, onZoomChanged: widget.onZoomChanged),
          onZoomChanged: widget.onZoomChanged,
          canChangePageFormat: false, canChangeOrientation: false,
          allowPrinting: true, allowSharing: true,
          pdfFileName: '${widget.date.toIso8601String().substring(0, 10)}_${widget.report?.id ?? 'preview'}_日報.pdf',
          build: _buildPreviewPdf,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.message,
    required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 46),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(SkoLanguageController.tr('再読み込み')),
            ),
          ],
        ),
      ),
    );
  }
}

String _captureStatusLabel(String? status) => SkoLanguageController.tr(switch (status) {
  'acquired' || 'uploaded' => '登録済み',
  'upload_failed' => '送信失敗',
  'failed' => '取得失敗',
  _ => '未登録',
});


class _ReportStepBadge extends StatelessWidget {
  const _ReportStepBadge(this.number);
  final String number;
  @override
  Widget build(BuildContext context) => SizedBox(width: 40, height: 40,
    child: Center(child: Text(number, style: TextStyle(
      color: Theme.of(context).colorScheme.primary,
      fontSize: 28, fontWeight: FontWeight.w800))));
}


