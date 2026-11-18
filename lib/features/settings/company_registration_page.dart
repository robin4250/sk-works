import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../companies/trade_company_invitation_page.dart'
    show companySignupInvitationLink;

import '../../international/countries/jp/japan_phone_rules.dart';

class CompanyRegistrationPage extends StatefulWidget {
  const CompanyRegistrationPage({
    super.key,
    required this.client,
    this.review = false,
  });

  final SupabaseClient client;
  final bool review;

  @override
  State<CompanyRegistrationPage> createState() =>
      _CompanyRegistrationPageState();
}

class _CompanyRegistrationPageState extends State<CompanyRegistrationPage> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _form = GlobalKey<FormState>();
  List<Map<String, dynamic>> _companies = [];
  List<Map<String, dynamic>> _requests = [];
  String? _company;
  String _purpose = 'sko';
  String? _error;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _run(_refresh, failure: '申請の読み込みに失敗しました。');
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _run(
    Future<void> Function() action, {
    required String failure,
  }) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on PostgrestException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.code == '23505'
            ? 'この番号は申請または承認済みです。'
            : error.code == '42501'
            ? 'この操作を行う権限がありません。'
            : failure;
      });
    } catch (_) {
      if (mounted) setState(() => _error = failure);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() async {
    final actor = widget.client.auth.currentUser?.id;
    final result =
        await widget.client.rpc(
              'company_registration_inbox',
              params: {'p_master': widget.review},
            )
            as Map;
    if (!mounted || widget.client.auth.currentUser?.id != actor) return;
    setState(() {
      _companies = List<Map<String, dynamic>>.from(result['companies'] as List);
      _requests = List<Map<String, dynamic>>.from(result['requests'] as List);
      if (!_companies.any((company) => company['id'] == _company)) {
        _company = _companies.length == 1
            ? _companies.single['id'] as String
            : null;
      }
    });
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    await _run(() async {
      await widget.client.rpc(
        'submit_company_registration',
        params: {
          'p_company_id': _company,
          'p_purpose': _purpose,
          'p_person_name': _name.text.trim(),
          'p_phone': JapanPhoneRules.normalize(_phone.text),
        },
      );
      if (!mounted) return;
      _name.clear();
      _phone.clear();
      await _refresh();
    }, failure: '申請を送信できませんでした。一覧を更新してご確認ください。');
  }

  Future<void> _review(Map<String, dynamic> request, String action) async {
    final actor = widget.client.auth.currentUser?.id;
    final approve = action == 'approve';
    final reissue = action == 'reissue';
    final title = reissue
        ? 'コードを再発行'
        : approve
        ? '承認'
        : '却下';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(
          '${request['company_name']}　${request['person_name']}\n${request['phone']}\n\n'
          '${reissue
              ? '再発行すると前のコードは失効します。'
              : approve
              ? '本人と電話番号を個別に確認した場合に承認してください。'
              : 'この申請を却下しますか？'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('戻る'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(title),
          ),
        ],
      ),
    );
    if (!mounted ||
        confirmed != true ||
        widget.client.auth.currentUser?.id != actor) {
      return;
    }

    await _run(() async {
      final code = await widget.client.rpc(
        'review_company_registration',
        params: {'p_request_id': request['id'], 'p_action': action},
      );
      if (!mounted || widget.client.auth.currentUser?.id != actor) return;
      if (code is String) {
        await _showCode(code, workPass: request['purpose'] == 'work_pass');
      }
      if (mounted) await _refresh();
    }, failure: '審査結果を確認できませんでした。一覧を更新してご確認ください。');
  }

  Future<void> _showCode(String code, {required bool workPass}) async {
    final invite = companySignupInvitationLink(
      code,
      workPass: workPass,
    ).toString();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(workPass ? 'ワークパス登録リンク' : 'SKO招待リンク'),
        content: const Text('確認済みの連絡先から招待する本人にリンクを渡してください。有効期限は24時間です。'),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: invite));
              if (dialogContext.mounted) {
                ScaffoldMessenger.of(
                  dialogContext,
                ).showSnackBar(const SnackBar(content: Text('招待リンクをコピーしました。')));
              }
            },
            child: const Text('招待リンクをコピー'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  String _purposeLabel(Object? purpose) =>
      purpose == 'work_pass' ? 'ワークパス' : 'SKO通常利用';

  Widget _requestCard(Map<String, dynamic> request) {
    final decision = request['decision'];
    final pending = decision == 'pending';
    final registered = request['registered'] == true;
    final status = switch (decision) {
      'approved' => registered ? '登録済み' : '承認済み・登録待ち',
      'rejected' => '却下',
      _ => '審査待ち',
    };
    final submitted = DateTime.tryParse(
      request['submitted_at'] as String? ?? '',
    )?.toLocal();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${request['company_name']}　${_purposeLabel(request['purpose'])}',
            ),
            const SizedBox(height: 4),
            Text('${request['person_name']}　${request['phone']}'),
            Text(
              submitted == null
                  ? status
                  : '$status · ${MaterialLocalizations.of(context).formatShortDate(submitted)}',
            ),
            if (widget.review &&
                (pending || (decision == 'approved' && !registered)))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 8,
                  children: [
                    if (pending) ...[
                      OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () => _review(request, 'reject'),
                        child: const Text('却下'),
                      ),
                      FilledButton(
                        onPressed: _busy
                            ? null
                            : () => _review(request, 'approve'),
                        child: const Text('承認'),
                      ),
                    ] else
                      OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () => _review(request, 'reissue'),
                        child: const Text('コード再発行'),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _applicationForm() => Form(
    key: _form,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _company,
          isExpanded: true,
          decoration: const InputDecoration(labelText: '申請元の会社'),
          items: _companies
              .map(
                (company) => DropdownMenuItem(
                  value: company['id'] as String,
                  child: Text(company['name'] as String),
                ),
              )
              .toList(),
          onChanged: _busy ? null : (value) => setState(() => _company = value),
          validator: (value) => value == null ? '申請元の会社を選択してください。' : null,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _purpose,
          decoration: const InputDecoration(labelText: '利用目的'),
          items: const [
            DropdownMenuItem(value: 'sko', child: Text('SKO通常利用')),
            DropdownMenuItem(value: 'work_pass', child: Text('ワークパス')),
          ],
          onChanged: _busy
              ? null
              : (value) => setState(() => _purpose = value!),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _name,
          enabled: !_busy,
          maxLength: 120,
          decoration: const InputDecoration(labelText: '登録する方の氏名'),
          validator: (value) =>
              value?.trim().isNotEmpty == true ? null : '氏名を入力してください。',
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _phone,
          enabled: !_busy,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: '登録する方の携帯電話番号'),
          validator: (value) => JapanPhoneRules.isSupportedMobile(value ?? '')
              ? null
              : '携帯電話番号を確認してください。',
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: const Text('会社から申請する'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.review ? '会社からの利用申請' : 'SKO・ワークパス利用申請'),
      actions: [
        IconButton(
          tooltip: '一覧を更新',
          onPressed: _busy
              ? null
              : () => _run(_refresh, failure: '申請の読み込みに失敗しました。'),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_busy) const LinearProgressIndicator(),
            if (_error case final error?)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (!widget.review && _companies.isNotEmpty) ...[
              _applicationForm(),
              const SizedBox(height: 24),
              Text('申請履歴', style: Theme.of(context).textTheme.titleMedium),
            ],
            if (!_busy && _error == null && _requests.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  !widget.review && _companies.isEmpty
                      ? '会社の管理者が申請できます。'
                      : '申請はありません。',
                ),
              ),
            ..._requests.map(_requestCard),
          ],
        ),
      ),
    ),
  );
}
