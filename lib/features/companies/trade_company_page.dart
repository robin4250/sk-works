import '../shared/trade_document_confirmation_dialog.dart';
import '../shared/standalone_trade_document_page.dart';
import 'trade_company_dialog.dart';
import '../../data/supabase_backend.dart';
import 'trade_company_invitation_page.dart';
import 'company_invite_recipient_picker.dart';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'company_contact_links.dart';
import 'company_contact_parser.dart';

import '../notifications/notification_bell.dart';
import '../../international/language_controller.dart';
import 'trade_company_repository.dart';
import 'company_link_page.dart';

class TradeCompanyPage extends StatefulWidget {
  const TradeCompanyPage({
    super.key,
    required this.mode,
    this.unified = false,
    this.onOpenDeliveries,
    this.repository,
  });
  final bool unified;
  final VoidCallback? onOpenDeliveries;
  final TradeCompanyPageMode mode;
  final TradeCompanyRepository? repository;

  @override
  State<TradeCompanyPage> createState() => _TradeCompanyPageState();
}

class _TradeCompanyPageState extends State<TradeCompanyPage> {
  late final _repository =
      widget.repository ?? TradeCompanyRepository.maybeCreate();
  bool _companyEditorOpen = false;
  List<TradeCompanyRecord> _items = const [];
  bool _loading = true;
  bool _linkEnabled = false;
  String? _error;

  String get _title => widget.unified
      ? SkoLanguageController.tr('連携会社登録')
      : widget.mode == TradeCompanyPageMode.customer ? '取引会社登録' : '協力会社登録';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repository = _repository;
    if (repository == null) {
      setState(() {
        _loading = false;
        _error = '会社データを利用できません。';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await repository.loadAll();
      var linkEnabled = false;
      try {
        final scope = repository.createLinkScope();
        try {
          await scope.loadContexts();
          linkEnabled = scope.contexts.isNotEmpty;
        } finally {
          await scope.close();
        }
      } catch (_) {
        // Older deployments retain their company directory until migration.
      }
      if (!mounted) return;
      setState(() {
        _items = items;
        _linkEnabled = linkEnabled;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  List<TradeCompanyRecord> get _visible => widget.unified ? _items : _items
      .where((item) {
        return widget.mode == TradeCompanyPageMode.customer
            ? item.isCustomer
            : item.isSubcontractor;
      })
      .toList(growable: false);

  Future<TradeCompanyPageMode?> _selectMode({TradeCompanyRecord? company}) {
    if (!widget.unified) return Future.value(widget.mode);
    if (company != null && company.isCustomer != company.isSubcontractor) {
      return Future.value(company.isCustomer
          ? TradeCompanyPageMode.customer : TradeCompanyPageMode.subcontractor);
    }
    return showDialog<TradeCompanyPageMode>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(SkoLanguageController.tr('区分')),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, TradeCompanyPageMode.customer),
            child: Text(SkoLanguageController.tr('取引会社')),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, TradeCompanyPageMode.subcontractor),
            child: Text(SkoLanguageController.tr('協力会社')),
          ),
        ],
      ),
    );
  }

  List<List<TradeCompanyRecord>> _directoryRows(List<TradeCompanyRecord> visible) {
    final grouped = <String, List<TradeCompanyRecord>>{};
    for (final company in visible) {
      final key = widget.unified && company.linkStatus == 'linked' &&
              company.linkedCompanyId.isNotEmpty
          ? 'linked:${company.linkedCompanyId}'
          : 'record:${company.id}';
      (grouped[key] ??= []).add(company);
    }
    return grouped.values.toList(growable: false);
  }

  Future<void> _openDirectoryRow(List<TradeCompanyRecord> records) async {
    if (records.length == 1) {
      await _openCompany(records.single);
      return;
    }
    final selected = await showDialog<TradeCompanyRecord>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('既存の会社データを選択'),
        children: [
          for (final record in records)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, record),
              child: Text('${record.name} / ${record.isCustomer && record.isSubcontractor
                  ? '取引会社・協力会社' : record.isCustomer ? '取引会社' : '協力会社'}'
                  '\n${record.address} ${_contractLabel(record.contractMethod)}'),
            ),
        ],
      ),
    );
    if (mounted && selected != null) await _openCompany(selected);
  }

  Future<void> _invite({TradeCompanyRecord? recipient}) async {
    final actor = SupabaseBackend.client.auth.currentUser?.id;
    if (actor == null) return;
    Future<void> openInvite(TradeCompanyRecord company) async {
      if (!mounted ||
          !_canInvite(company) ||
          SupabaseBackend.client.auth.currentUser?.id != actor) {
        return;
      }
      final mode = await _selectMode(company: company);
      if (!mounted || mode == null || SupabaseBackend.client.auth.currentUser?.id != actor) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TradeCompanyInvitationPage(
            client: SupabaseBackend.client,
            contact: company,
            mode: mode,
          ),
        ),
      );
      if (mounted) await _load();
    }

    if (recipient != null) {
      await openInvite(recipient);
      return;
    }
    var selected = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => CompanyInviteRecipientPicker(
        companies: _visible.where(_canInvite).toList(),
        allowDirect: false,
        onSelected: (company) {
          if (selected || !mounted || company == null) return;
          selected = true;
          Navigator.of(sheetContext).pop();
          openInvite(company);
        },
      ),
    );
  }

  bool _canInvite(TradeCompanyRecord company) =>
      company.linkStatus != 'linked' && company.linkedCompanyId.isEmpty;

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final directoryRows = _directoryRows(visible);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: kToolbarHeight,
        title: Text(
          _title,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          TextButton.icon(
            onPressed: _loading || _repository == null ? null : _invite,
            icon: const Icon(Icons.person_add_alt_1_outlined),
            label: const Text('SKO招待'),
          ),
          if (_linkEnabled)
            IconButton(
              tooltip: '会社を検索・連携申請',
              icon: const Icon(Icons.search),
              onPressed: _repository == null
                  ? null
                  : () async {
                      final mode = await _selectMode();
                      if (!context.mounted || mode == null) return;
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => CompanyLinkPage(
                            repository: _repository,
                            mode: mode,
                          ),
                        ),
                      );
                      if (mounted) await _load();
                    },
            ),
          if (widget.onOpenDeliveries != null)
            IconButton(
              tooltip: SkoLanguageController.tr('受信した社員・書類'),
              icon: const Icon(Icons.folder_shared_outlined),
              onPressed: widget.onOpenDeliveries,
            ),
          const SkoNotificationBell(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : _register,
        icon: const Icon(Icons.add_business_outlined),
        label: const Text('登録'),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? _ErrorState(message: _error!, onRetry: _load)
            : visible.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Text(
                    widget.unified
                        ? '連携会社はまだ登録されていません'
                        : widget.mode == TradeCompanyPageMode.customer
                        ? '取引会社はまだ登録されていません\nSKO連携なしでも登録できます'
                        : '協力会社はまだ登録されていません\nSKO連携なしでも登録できます',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                  itemCount: directoryRows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final records = directoryRows[index];
                    final item = records.first;
                    final companyRoles = [
                      if (widget.unified && records.any((record) => record.isCustomer))
                        SkoLanguageController.tr('取引会社'),
                      if (widget.unified && records.any((record) => record.isSubcontractor))
                        SkoLanguageController.tr('協力会社'),
                    ].join('・');
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Icon(
                            item.linkStatus == 'linked'
                                ? Icons.link
                                : Icons.business_outlined,
                          ),
                        ),
                        title: Text(
                          item.name,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        subtitle: Text(
                          [
                            if (companyRoles.isNotEmpty) companyRoles,
                            _linkLabel(item.linkStatus),
                            if (records.length > 1)
                              '会社データ ${records.length}件'
                            else
                              _contractLabel(item.contractMethod),
                          ].join(' / '),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _openDirectoryRow(records),
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }

  Future<void> _register() async {
    final repository = _repository;
    if (repository == null || _companyEditorOpen) return;
    _companyEditorOpen = true;
    try {
      final mode = await _selectMode();
      if (!mounted || mode == null) return;
      final id = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _CompanyRegistrationDialog(
          title: _title,
          onSave: (draft) {
            final same = _items.where(
              (item) =>
                  widget.unified
                      ? draft.corporateNumber.trim().isNotEmpty &&
                          item.corporateNumber.trim() == draft.corporateNumber.trim()
                      : item.name.trim().toLowerCase() == draft.name.trim().toLowerCase(),
            );
            if (widget.unified && same.length > 1) {
              throw StateError('同じ法人番号の会社が複数あります。登録済みの会社を確認してください。');
            }
            final existing = same.isEmpty ? null : same.first;
            final desiredRole = mode == TradeCompanyPageMode.customer
                ? 'customer'
                : 'subcontractor';
            final role = existing == null || existing.tradeRole == desiredRole
                ? desiredRole
                : 'both';
            return repository.saveCompany(
              id: existing?.id,
              name: draft.name,
              tradeRole: role,
              postalCode: draft.postalCode,
              address: draft.address,
              phone: draft.phone,
              email: draft.email,
              corporateNumber: draft.corporateNumber,
              notes: draft.notes,
              representativeName: draft.representativeName,
              representativePhone: draft.representativePhone,
            );
          },
        ),
      );
      if (id == null || !mounted) return;
      await _load();
      if (!mounted) return;
      final saved = _items.where((item) => item.id == id);
      if (saved.isNotEmpty) await _offerLinkMerge(saved.first);
    } finally {
      _companyEditorOpen = false;
    }
  }

  Future<void> _openCompany(TradeCompanyRecord item) async {
    final action = await showDialog<_CompanyAction>(
      context: context,
      builder: (dialogContext) => TradeCompanyDialog(
        title: Text(item.name),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _detailLine(
                  '区分',
                  widget.unified && item.isCustomer && item.isSubcontractor
                      ? '取引会社・協力会社'
                      : (widget.unified ? item.isCustomer : widget.mode == TradeCompanyPageMode.customer)
                      ? '取引会社' : '協力会社',
                ),
                _detailLine('SKO連携', _linkLabel(item.linkStatus)),
                if (widget.unified)
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(dialogContext).pop(_CompanyAction.siteDefault),
                    icon: const Icon(Icons.tune),
                    label: const Text('現場での初期値'),
                  ),
                if (_canInvite(item))
                  OutlinedButton.icon(
                    key: const ValueKey('trade-company-sko-invite'),
                    onPressed: () =>
                        Navigator.of(dialogContext).pop(_CompanyAction.invite),
                    icon: const Icon(Icons.person_add_alt_1_outlined),
                    label: const Text('SKO招待'),
                  ),
                _detailLine('郵便番号', item.postalCode),
                _detailLine('住所', item.address),
                _detailLine('電話番号', item.phone),
                _detailLine('代表者氏名', item.representativeName),
                _detailLine('代表者電話番号', item.representativePhone),
                _detailLine('メール', item.email),
                _detailLine('法人番号', item.corporateNumber),
                _detailLine('備考', item.notes),
                const Divider(height: 24),
                _detailLine('契約方式', _contractLabel(item.contractMethod)),
                if (item.contractMethod == 'daily')
                  _detailLine('1日単価', _yen(item.dailyRateYen)),
                if (item.contractMethod == 'monthly')
                  _detailLine('月単価', _yen(item.monthlyRateYen)),
                if (item.contractMethod == 'square_meter') ...[
                  _detailLine('平米単価', _yen(item.squareMeterUnitPriceYen)),
                  _detailLine('平米数', _number(item.squareMeterQuantity)),
                ],
                if (item.contractMethod == 'contract')
                  _detailLine('請負金額', _yen(item.contractAmountYen)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('閉じる'),
          ),
          TextButton.icon(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_CompanyAction.delete),
            icon: const Icon(Icons.delete_outline),
            label: const Text('削除'),
          ),
          OutlinedButton.icon(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_CompanyAction.edit),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('会社情報を編集'),
          ),
          OutlinedButton.icon(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_CompanyAction.source),
            icon: const Icon(Icons.rule_outlined),
            label: const Text('計算元を確認・変更'),
          ),
          if (widget.unified ? item.isCustomer : widget.mode == TradeCompanyPageMode.customer)
            OutlinedButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(_CompanyAction.acceptance),
              icon: const Icon(Icons.description_outlined),
              label: const Text('注文請書生成'),
            ),
          if (widget.unified ? item.isSubcontractor : widget.mode == TradeCompanyPageMode.subcontractor)
            OutlinedButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(_CompanyAction.order),
              icon: const Icon(Icons.description_outlined),
              label: const Text('注文書生成'),
            ),
          if (item.linkStatus == 'linked')
            OutlinedButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(_CompanyAction.receivedDocuments),
              icon: const Icon(Icons.inbox_outlined),
              label: Text(SkoLanguageController.tr('受領した承認済み書類')),
            ),
          FilledButton.icon(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_CompanyAction.contract),
            icon: const Icon(Icons.payments_outlined),
            label: const Text('契約設定'),
          ),
        ],
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _CompanyAction.acceptance:
      case _CompanyAction.order:
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => StandaloneTradeDocumentPage(
              tradeCompanyId: item.id,
              acceptance: action == _CompanyAction.acceptance,
            ),
          ),
        );

      case _CompanyAction.receivedDocuments:
        await openReceivedTradeDocuments(context, item.id, item.name);

      case _CompanyAction.invite:
        await _invite(recipient: item);
      case _CompanyAction.edit:
        await _editCompany(item);
      case _CompanyAction.siteDefault:
        await _editSiteDefault(item);
      case _CompanyAction.contract:
        await _editContract(item);
      case _CompanyAction.delete:
        await _deleteCompany(item);
      case _CompanyAction.source:
        try {
          await _resolveConflicts(item.id, revise: true);
        } catch (error) {
          if (!mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('計算元を変更できませんでした: $error')));
        }
    }
  }

  Future<void> _launchContact(Uri uri) async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('電話・地図を開けませんでした')));
    }
  }

  Widget _detailLine(String label, String value) {
    final display = value.trim().isEmpty ? '未登録' : value;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          Expanded(
            child: label == '備考'
                ? CompanyNotesLinks(text: display, onOpen: _launchContact)
                : CompanyContactValue(
                    text: display,
                    uri: value.trim().isEmpty
                        ? null
                        : label == '住所'
                        ? companyAddressUri(value)
                        : ['電話番号', '代表者電話番号'].contains(label)
                        ? companyPhoneUri(value)
                        : null,
                    onOpen: _launchContact,
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _editSiteDefault(TradeCompanyRecord item) async {
    final repository = _repository;
    final token = SupabaseBackend.isInitialized
        ? SupabaseBackend.client.auth.currentSession?.accessToken : null;
    if (repository == null || token == null || _companyEditorOpen) return;
    _companyEditorOpen = true;
    try {
      final current = await repository.siteDefaultRole(
        tradeCompanyId: item.id, sessionToken: token,
      );
      if (!mounted) return;
      final choices = {'customer': '取引会社', 'subcontractor': '協力会社', 'unset': '未設定'};
      final selected = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text('${item.name}の現場での初期値'),
          children: [
            for (final choice in choices.entries)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, choice.key),
                child: Text(choice.key == current ? '${choice.value}（現在）' : choice.value),
              ),
          ],
        ),
      );
      if (!mounted || selected == null || selected == current) return;
      await repository.siteDefaultRole(
        tradeCompanyId: item.id, sessionToken: token, role: selected,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('現場での初期値を保存しました。')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('現場での初期値を確認できませんでした。\n$error')),
        );
      }
    } finally {
      _companyEditorOpen = false;
    }
  }

  Future<void> _editCompany(TradeCompanyRecord item) async {
    final repository = _repository;
    if (repository == null || _companyEditorOpen) return;
    _companyEditorOpen = true;
    try {
      final id = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _CompanyRegistrationDialog(
          title: _title,
          initial: item,
          onSave: (draft) => repository.saveCompany(
            id: item.id,
            name: draft.name,
            tradeRole: item.tradeRole,
            postalCode: draft.postalCode,
            address: draft.address,
            phone: draft.phone,
            email: draft.email,
            corporateNumber: draft.corporateNumber,
            notes: draft.notes,
            representativeName: draft.representativeName,
            representativePhone: draft.representativePhone,
          ),
        ),
      );
      if (id != null && mounted) await _load();
    } finally {
      _companyEditorOpen = false;
    }
  }

  Future<void> _editContract(TradeCompanyRecord item) async {
    final result = await showDialog<_ContractDraft>(
      context: context,
      builder: (_) => _ContractDialog(item: item),
    );
    if (result == null || _repository == null) return;

    try {
      await _repository.saveContract(
        tradeCompanyId: item.id,
        contractMethod: result.method,
        dailyRateYen: result.dailyRate,
        monthlyRateYen: result.monthlyRate,
        squareMeterUnitPriceYen: result.squareMeterRate,
        squareMeterQuantity: result.squareMeters,
        contractAmountYen: result.contractAmount,
      );
      await _offerLinkMerge(item);
      await _resolveConflicts(item.id);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('契約設定を保存しました')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('契約設定を保存できませんでした: $error')));
    }
  }

  Future<void> _deleteCompany(TradeCompanyRecord item) async {
    if (_repository == null) return;
    final both = item.tradeRole == 'both';
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => TradeCompanyDialog(
        title: const Text('会社を削除しますか？'),
        content: Text(
          both
              ? '${item.name} は取引会社・協力会社の両方に登録されています。削除すると両方の一覧から消え、契約設定も削除されます。'
              : '${item.name} を削除します。関連する契約設定も削除されます。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('削除する'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final deleted = await _repository.deleteCompany(item.id);
      await _load();
      if (!mounted) return;
      final stillExists = _items.any((value) => value.id == item.id);
      if (!deleted || stillExists) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('会社を削除できませんでした。参照中のデータを確認してください。')),
        );
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('会社を削除しました')));
    } catch (error) {
      if (!mounted) return;
      final message = error.toString().replaceFirst('Bad state: ', '');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  static String _yen(int value) => '¥${value.toString()}';

  static String _number(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toString();
  }

  Future<void> _offerLinkMerge(TradeCompanyRecord item) async {
    // Linking is explicit and requires the other company's approval.
    // Saving contact or contract information never initiates a merge.
  }

  Future<void> _resolveConflicts(
    String tradeCompanyId, {
    bool revise = false,
  }) async {
    final repository = _repository;
    if (repository == null) return;
    final conflicts = await repository.calculationConflicts(tradeCompanyId);

    final choices = conflicts
        .where(
          (item) =>
              item.outputType != 'payment_certificate' &&
              (revise || (item.conflict && item.selectedSource == null)),
        )
        .toList(growable: false);
    if (revise && choices.isEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('変更できる現場の請求書・給与の計算元がありません。')),
      );
    }
    for (final conflict in choices) {
      if (!mounted) return;
      final source = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => TradeCompanyDialog(
          title: Text(revise ? '計算元を確認・変更' : '計算設定が重複しています'),
          content: Text(
            '${conflict.siteName} の ${conflict.outputLabel} について、'
            '現在の選択：${conflict.selectedSource == 'trade_company'
                ? '会社契約'
                : conflict.selectedSource == 'site'
                ? '管理現場'
                : '未選択（管理現場）'}\n'
            '管理現場：${conflict.siteSettingConfigured ? '設定済み' : '未設定'} / '
            '会社契約：${conflict.tradeCompanySettingConfigured ? '設定済み' : '未設定'}\n\n'
            '計算に使う設定を選んでください。',
          ),
          actions: [
            if (revise)
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('変更しない'),
              ),
            OutlinedButton(
              onPressed: () => Navigator.of(dialogContext).pop('site'),
              child: const Text('管理現場の設定を使う'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop('trade_company'),
              child: Text(
                widget.mode == TradeCompanyPageMode.customer
                    ? '取引会社の契約を使う'
                    : '協力会社の契約を使う',
              ),
            ),
          ],
        ),
      );
      if (source == null) continue;
      await repository.selectCalculationSource(
        siteId: conflict.siteId,
        outputType: conflict.outputType,
        tradeCompanyId: tradeCompanyId,
        source: source,
      );
    }
  }

  String _linkLabel(String value) => switch (value) {
    'linked' when widget.unified => '連携済み',
    _ when widget.unified => '仮登録',
    'linked' => 'SKO連携済み',
    'merge_pending' => '統合確認待ち',
    _ => '連携なし',
  };

  String _contractLabel(String value) => switch (value) {
    'daily' => '1日単価',
    'monthly' => '月単価',
    'square_meter' => '平米単価',
    'contract' => '請負',
    _ => '契約未設定',
  };
}

enum _CompanyAction { edit, siteDefault, contract, delete, source, invite, acceptance, order, receivedDocuments }

class _CompanyDraft {
  const _CompanyDraft({
    required this.name,
    required this.postalCode,
    required this.address,
    required this.phone,
    required this.email,
    required this.corporateNumber,
    required this.notes,
    required this.representativeName,
    required this.representativePhone,
  });

  final String name;
  final String postalCode;
  final String address;
  final String phone;
  final String email;
  final String corporateNumber;
  final String notes;
  final String representativeName;
  final String representativePhone;
}

class _CompanyRegistrationDialog extends StatefulWidget {
  const _CompanyRegistrationDialog({
    required this.title,
    required this.onSave,
    this.initial,
  });
  final Future<String> Function(_CompanyDraft draft) onSave;
  final String title;
  final TradeCompanyRecord? initial;

  @override
  State<_CompanyRegistrationDialog> createState() =>
      _CompanyRegistrationDialogState();
}

class _CompanyRegistrationDialogState
    extends State<_CompanyRegistrationDialog> {
  bool _saving = false;
  String? _savedId;
  String? _error;
  late final TextEditingController _name;
  late final TextEditingController _postalCode;
  late final TextEditingController _address;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _corporateNumber;
  late final TextEditingController _notes;
  late final TextEditingController _representativeName;
  late final TextEditingController _representativePhone;

  @override
  void initState() {
    super.initState();
    final item = widget.initial;
    _name = TextEditingController(text: item?.name ?? '');
    _postalCode = TextEditingController(text: item?.postalCode ?? '');
    _address = TextEditingController(text: item?.address ?? '');
    _phone = TextEditingController(text: item?.phone ?? '');
    _email = TextEditingController(text: item?.email ?? '');
    _corporateNumber = TextEditingController(text: item?.corporateNumber ?? '');
    _notes = TextEditingController(text: item?.notes ?? '');
    _representativeName = TextEditingController(
      text: item?.representativeName ?? '',
    );
    _representativePhone = TextEditingController(
      text: item?.representativePhone ?? '',
    );
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _postalCode,
      _address,
      _phone,
      _email,
      _corporateNumber,
      _notes,
      _representativeName,
      _representativePhone,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _savedId != null) return;
    if (_name.text.trim().isEmpty) {
      setState(() => _error = '会社名を入力してください。');
      return;
    }
    final draft = _CompanyDraft(
      name: _name.text.trim(),
      postalCode: _postalCode.text.trim(),
      address: _address.text.trim(),
      phone: _phone.text.trim(),
      email: _email.text.trim(),
      corporateNumber: _corporateNumber.text.trim(),
      notes: _notes.text.trim(),
      representativeName: _representativeName.text.trim(),
      representativePhone: _representativePhone.text.trim(),
    );
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final id = await widget.onSave(draft);
      if (!mounted) return;
      if (id.isEmpty) throw StateError('保存結果を確認できません。');
      setState(() => _savedId = id);
    } catch (error) {
      if (mounted) {
        setState(() => _error = '保存できませんでした。入力を確認して再試行してください。 $error');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving && _savedId == null,
      child: TradeCompanyDialog(
        title: Text(
          _savedId != null
              ? (widget.initial == null ? '登録しました' : '更新しました')
              : (widget.initial == null
                    ? '${widget.title}を登録'
                    : '${widget.title}を編集'),
        ),
        content: _savedId != null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    '${_name.text.trim()}の会社情報を${widget.initial == null ? '登録' : '更新'}しました。',
                  ),
                  const SizedBox(height: 8),
                  const Text('一覧で保存した内容を確認できます。'),
                ],
              )
            : AbsorbPointer(
                absorbing: _saving,
                child: SizedBox(
                  width: 460,
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              _error!,
                              key: const ValueKey('company-save-error'),
                            ),
                          ),
                        TextField(
                          enabled: !_saving,
                          controller: _name,
                          decoration: const InputDecoration(labelText: '会社名 *'),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          enabled: !_saving,
                          controller: _phone,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(labelText: '電話番号'),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          enabled: !_saving,
                          controller: _postalCode,
                          decoration: const InputDecoration(labelText: '郵便番号'),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          enabled: !_saving,
                          controller: _address,
                          decoration: const InputDecoration(labelText: '住所'),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          enabled: !_saving,
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(labelText: 'メール'),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          enabled: !_saving,
                          controller: _corporateNumber,
                          decoration: const InputDecoration(labelText: '法人番号'),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          enabled: !_saving,
                          controller: _representativeName,
                          decoration: const InputDecoration(labelText: '代表者氏名'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          enabled: !_saving,
                          controller: _representativePhone,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: '代表者電話番号',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          enabled: !_saving,
                          controller: _notes,
                          maxLines: 3,
                          decoration: const InputDecoration(labelText: '備考'),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'SKO連携は必須ではありません。連携なしのまま請求書・支払証明書用の会社として利用できます。',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
        actions: _savedId != null
            ? [
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(_savedId),
                  child: const Text('一覧で確認'),
                ),
              ]
            : [
                TextButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  child: const Text('キャンセル'),
                ),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(
                    _saving
                        ? (widget.initial == null ? '登録中…' : '更新中…')
                        : (widget.initial == null ? '登録' : '保存'),
                  ),
                ),
              ],
      ),
    );
  }
}

class _ContractDraft {
  const _ContractDraft({
    required this.method,
    required this.dailyRate,
    required this.monthlyRate,
    required this.squareMeterRate,
    required this.squareMeters,
    required this.contractAmount,
  });

  final String method;
  final int dailyRate;
  final int monthlyRate;
  final int squareMeterRate;
  final double squareMeters;
  final int contractAmount;
}

class _ContractDialog extends StatefulWidget {
  const _ContractDialog({required this.item});
  final TradeCompanyRecord item;

  @override
  State<_ContractDialog> createState() => _ContractDialogState();
}

class _ContractDialogState extends State<_ContractDialog> {
  late String _method;
  late final TextEditingController _daily;
  late final TextEditingController _monthly;
  late final TextEditingController _squareRate;
  late final TextEditingController _squareMeters;
  late final TextEditingController _contract;

  @override
  void initState() {
    super.initState();
    _method = widget.item.contractMethod;
    _daily = TextEditingController(text: widget.item.dailyRateYen.toString());
    _monthly = TextEditingController(
      text: widget.item.monthlyRateYen.toString(),
    );
    _squareRate = TextEditingController(
      text: widget.item.squareMeterUnitPriceYen.toString(),
    );
    _squareMeters = TextEditingController(
      text: _number(widget.item.squareMeterQuantity),
    );
    _contract = TextEditingController(
      text: widget.item.contractAmountYen.toString(),
    );
  }

  @override
  void dispose() {
    for (final controller in [
      _daily,
      _monthly,
      _squareRate,
      _squareMeters,
      _contract,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TradeCompanyDialog(
      title: Text(widget.item.name),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.item.linkStatus == 'linked' ? 'SKO連携済み' : 'SKO連携なし',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _method,
                decoration: const InputDecoration(labelText: '契約方式'),
                items: const [
                  DropdownMenuItem(value: 'none', child: Text('未設定')),
                  DropdownMenuItem(value: 'daily', child: Text('1日単価')),
                  DropdownMenuItem(value: 'monthly', child: Text('月単価')),
                  DropdownMenuItem(value: 'square_meter', child: Text('平米単価')),
                  DropdownMenuItem(value: 'contract', child: Text('請負')),
                ],
                onChanged: (value) =>
                    setState(() => _method = value ?? _method),
              ),
              const SizedBox(height: 12),
              if (_method == 'daily')
                _MoneyField(controller: _daily, label: '1日単価'),
              if (_method == 'monthly')
                _MoneyField(controller: _monthly, label: '月単価'),
              if (_method == 'square_meter') ...[
                _MoneyField(controller: _squareRate, label: '平米単価'),
                const SizedBox(height: 10),
                TextField(
                  controller: _squareMeters,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: '平米数'),
                ),
              ],
              if (_method == 'contract')
                _MoneyField(controller: _contract, label: '請負金額'),
              const SizedBox(height: 12),
              const Text('管理現場にも金額設定がある場合は、保存後にどちらを計算へ使うか選択画面を表示します。'),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: () {
            final squareRate = int.tryParse(_squareRate.text) ?? 0;
            final squareMeters = double.tryParse(_squareMeters.text) ?? 0;
            if (_method == 'square_meter' &&
                (squareRate <= 0 || squareMeters <= 0)) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('平米単価と平米数を入力してください')),
              );
              return;
            }
            Navigator.of(context).pop(
              _ContractDraft(
                method: _method,
                dailyRate: int.tryParse(_daily.text) ?? 0,
                monthlyRate: int.tryParse(_monthly.text) ?? 0,
                squareMeterRate: squareRate,
                squareMeters: squareMeters,
                contractAmount: int.tryParse(_contract.text) ?? 0,
              ),
            );
          },
          child: const Text('保存'),
        ),
      ],
    );
  }

  static String _number(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toString();
  }
}

class _MoneyField extends StatelessWidget {
  const _MoneyField({required this.controller, required this.label});
  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
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
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('再読み込み'),
            ),
          ],
        ),
      ),
    );
  }
}
