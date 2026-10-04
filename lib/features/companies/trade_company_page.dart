import 'package:flutter/material.dart';

import '../notifications/notification_bell.dart';
import 'trade_company_repository.dart';

class TradeCompanyPage extends StatefulWidget {
  const TradeCompanyPage({super.key, required this.mode});
  final TradeCompanyPageMode mode;

  @override
  State<TradeCompanyPage> createState() => _TradeCompanyPageState();
}

class _TradeCompanyPageState extends State<TradeCompanyPage> {
  final _repository = TradeCompanyRepository.maybeCreate();
  List<TradeCompanyRecord> _items = const [];
  bool _loading = true;
  String? _error;

  String get _title =>
      widget.mode == TradeCompanyPageMode.customer ? '取引会社' : '下請け会社';

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
      if (!mounted) return;
      setState(() {
        _items = items;
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

  List<TradeCompanyRecord> get _visible => _items.where((item) {
        return widget.mode == TradeCompanyPageMode.customer
            ? item.isCustomer
            : item.isSubcontractor;
      }).toList(growable: false);

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    return Scaffold(
      appBar: AppBar(
        title: Text(_title, style: const TextStyle(fontWeight: FontWeight.w900)),
        actions: const [SkoNotificationBell()],
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
                            widget.mode == TradeCompanyPageMode.customer
                                ? '取引会社はまだ登録されていません\nSKO連携なしでも登録できます'
                                : '下請け会社はまだ登録されていません\nSKO連携なしでも登録できます',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                          itemCount: visible.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final item = visible[index];
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
                                  '${_linkLabel(item.linkStatus)} / '
                                  '${_contractLabel(item.contractMethod)}',
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => _openCompany(item),
                              ),
                            );
                          },
                        ),
                      ),
      ),
    );
  }

  Future<void> _register() async {
    final draft = await showDialog<_CompanyDraft>(
      context: context,
      builder: (_) => _CompanyRegistrationDialog(title: _title),
    );
    if (draft == null || _repository == null) return;

    final same = _items.where(
      (item) =>
          item.name.trim().toLowerCase() == draft.name.trim().toLowerCase(),
    );
    final existing = same.isEmpty ? null : same.first;
    final desiredRole = widget.mode == TradeCompanyPageMode.customer
        ? 'customer'
        : 'subcontractor';
    final role = existing == null || existing.tradeRole == desiredRole
        ? desiredRole
        : 'both';

    try {
      final id = await _repository.saveCompany(
        id: existing?.id,
        name: draft.name,
        tradeRole: role,
        postalCode: draft.postalCode,
        address: draft.address,
        phone: draft.phone,
        email: draft.email,
        corporateNumber: draft.corporateNumber,
      );
      await _load();
      if (!mounted) return;
      final saved = _items.where((item) => item.id == id);
      if (saved.isNotEmpty) await _offerLinkMerge(saved.first);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('登録できませんでした: $error')),
      );
    }
  }

  Future<void> _openCompany(TradeCompanyRecord item) async {
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('契約設定を保存しました')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('契約設定を保存できませんでした: $error')),
      );
    }
  }

  Future<void> _offerLinkMerge(TradeCompanyRecord item) async {
    final repository = _repository;
    if (repository == null || item.linkStatus == 'linked') return;

    final candidates = await repository.linkCandidates(item.id);
    if (!mounted || candidates.isEmpty) return;

    final candidate = await showDialog<TradeCompanyLinkCandidate>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('SKO連携候補が見つかりました'),
        content: SizedBox(
          width: 460,
          child: ListView(
            shrinkWrap: true,
            children: [
              const Text(
                '会社名・電話番号・住所などが近いSKO登録会社があります。'
                '同じ会社の場合だけ統合してください。',
              ),
              const SizedBox(height: 12),
              for (final value in candidates)
                Card(
                  child: ListTile(
                    title: Text(value.companyName),
                    subtitle: Text([
                      if (value.phone.isNotEmpty) value.phone,
                      if (value.address.isNotEmpty) value.address,
                      '一致度 ${value.matchScore}',
                    ].join('\n')),
                    onTap: () => Navigator.of(dialogContext).pop(value),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('今は連携しない'),
          ),
        ],
      ),
    );

    if (candidate == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('会社データを統合しますか？'),
        content: Text(
          '${item.name}\n↓\n${candidate.companyName}\n\n'
          '同じ会社であることを確認してから統合してください。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('戻る'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('確認して統合'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await repository.confirmLink(
      tradeCompanyId: item.id,
      linkedCompanyId: candidate.companyId,
    );
  }

  Future<void> _resolveConflicts(String tradeCompanyId) async {
    final repository = _repository;
    if (repository == null) return;
    final conflicts = await repository.calculationConflicts(tradeCompanyId);

    for (final conflict in conflicts.where(
      (item) => item.conflict && item.selectedSource == null,
    )) {
      if (!mounted) return;
      final source = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('計算設定が重複しています'),
          content: Text(
            '${conflict.siteName} の ${conflict.outputLabel} について、'
            '管理現場と会社契約の両方に金額設定があります。\n\n'
            '計算に使う設定を選んでください。',
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.of(dialogContext).pop('site'),
              child: const Text('管理現場の設定を使う'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop('trade_company'),
              child: Text(
                widget.mode == TradeCompanyPageMode.customer
                    ? '取引会社の契約を使う'
                    : '下請け会社の契約を使う',
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

class _CompanyDraft {
  const _CompanyDraft({
    required this.name,
    required this.postalCode,
    required this.address,
    required this.phone,
    required this.email,
    required this.corporateNumber,
  });

  final String name;
  final String postalCode;
  final String address;
  final String phone;
  final String email;
  final String corporateNumber;
}

class _CompanyRegistrationDialog extends StatefulWidget {
  const _CompanyRegistrationDialog({required this.title});
  final String title;

  @override
  State<_CompanyRegistrationDialog> createState() =>
      _CompanyRegistrationDialogState();
}

class _CompanyRegistrationDialogState
    extends State<_CompanyRegistrationDialog> {
  final _name = TextEditingController();
  final _postalCode = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _corporateNumber = TextEditingController();

  @override
  void dispose() {
    for (final controller in [
      _name,
      _postalCode,
      _address,
      _phone,
      _email,
      _corporateNumber,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.title}を登録'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: '会社名 *'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: '電話番号'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _postalCode,
                decoration: const InputDecoration(labelText: '郵便番号'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _address,
                decoration: const InputDecoration(labelText: '住所'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'メール'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _corporateNumber,
                decoration: const InputDecoration(labelText: '法人番号'),
              ),
              const SizedBox(height: 10),
              const Text(
                'SKO連携は必須ではありません。連携なしのまま請求書・支払証明書用の会社として利用できます。',
              ),
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
            if (_name.text.trim().isEmpty) return;
            Navigator.of(context).pop(
              _CompanyDraft(
                name: _name.text.trim(),
                postalCode: _postalCode.text.trim(),
                address: _address.text.trim(),
                phone: _phone.text.trim(),
                email: _email.text.trim(),
                corporateNumber: _corporateNumber.text.trim(),
              ),
            );
          },
          child: const Text('登録'),
        ),
      ],
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
    _monthly =
        TextEditingController(text: widget.item.monthlyRateYen.toString());
    _squareRate = TextEditingController(
      text: widget.item.squareMeterUnitPriceYen.toString(),
    );
    _squareMeters = TextEditingController(
      text: _number(widget.item.squareMeterQuantity),
    );
    _contract =
        TextEditingController(text: widget.item.contractAmountYen.toString());
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
    return AlertDialog(
      title: Text(widget.item.name),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.item.linkStatus == 'linked'
                      ? 'SKO連携済み'
                      : 'SKO連携なし',
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
                  DropdownMenuItem(
                    value: 'square_meter',
                    child: Text('平米単価'),
                  ),
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
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: '平米数'),
                ),
              ],
              if (_method == 'contract')
                _MoneyField(controller: _contract, label: '請負金額'),
              const SizedBox(height: 12),
              const Text(
                '管理現場にも金額設定がある場合は、保存後にどちらを計算へ使うか選択画面を表示します。',
              ),
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
