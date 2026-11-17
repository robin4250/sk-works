import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../international/countries/jp/japan_phone_rules.dart';
import '../referrals/registration_completion_page.dart';
import 'trade_company_repository.dart';

const customerInvitationTitle = '取引会社への招待';
const companySignupInvitationTitle = 'SKO招待・会社登録';
const workPassInvitationTitle = 'ワークパス登録';

Uri companySignupInvitationLink(String code, {bool workPass = false}) {
  final route = workPass ? 'work_pass' : 'sko';
  return Uri.https(
    'app.skojapan.com',
    '/',
  ).replace(fragment: '/?${route}_invite=$code');
}

({String code, String title})? readTradeCompanyInvitation(Uri uri) {
  final match = RegExp(
    r'^/?[?](customer|subcontractor|sko|work_pass)_invite=([a-f0-9]{48})$',
  ).firstMatch(uri.fragment);
  if (match == null) return null;
  return (
    code: match.group(2)!,
    title: switch (match.group(1)) {
      'customer' => customerInvitationTitle,
      'subcontractor' => '協力会社への招待',
      'work_pass' => workPassInvitationTitle,
      _ => companySignupInvitationTitle,
    },
  );
}

class TradeCompanyInvitationPage extends StatefulWidget {
  const TradeCompanyInvitationPage({
    super.key,
    required this.client,
    required this.contact,
    required this.mode,
  });
  final SupabaseClient client;
  final TradeCompanyRecord contact;
  final TradeCompanyPageMode mode;

  @override
  State<TradeCompanyInvitationPage> createState() =>
      _TradeCompanyInvitationPageState();
}

class _TradeCompanyInvitationPageState
    extends State<TradeCompanyInvitationPage> {
  late final _phone = TextEditingController(
    text: widget.contact.representativePhone,
  );
  DateTime _start = DateTime.now();
  String? _link;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _prepare() async {
    if (!JapanPhoneRules.isSupportedMobile(_phone.text)) {
      setState(() => _error = '招待する代表者の携帯電話番号を確認してください。');
      return;
    }
    final actor = widget.client.auth.currentUser?.id;
    setState(() {
      _busy = true;
      _link = null;
      _error = null;
    });
    try {
      final code = await widget.client.rpc(
        'prepare_trade_company_invitation',
        params: {
          'p_trade_company_id': widget.contact.id,
          'p_sender_role': widget.mode.name,
          'p_phone': JapanPhoneRules.normalize(_phone.text),
          'p_start_month': DateTime(
            _start.year,
            _start.month,
          ).toIso8601String().split('T').first,
        },
      );
      if (!mounted ||
          actor != widget.client.auth.currentUser?.id ||
          code is! String) {
        return;
      }
      final link = Uri.https(
        'app.skojapan.com',
        '/',
      ).replace(fragment: '/?${widget.mode.name}_invite=$code');
      setState(() => _link = link.toString());
    } on PostgrestException catch (error) {
      if (mounted) {
        setState(
          () => _error = error.message.startsWith('会社')
              ? error.message
              : '招待を発行できませんでした。連携設定と登録状況をご確認ください。',
        );
      }
    } catch (_) {
      if (mounted) setState(() => _error = '招待を発行できませんでした。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('会社をSKOに招待')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              widget.contact.name,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              widget.mode == TradeCompanyPageMode.customer
                  ? '相手を取引会社として招待します。相手側では自社が協力会社になります。'
                  : '相手を協力会社として招待します。相手側では自社が取引会社になります。',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _phone,
              enabled: !_busy && _link == null,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: '代表者の携帯電話番号'),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: _start,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (mounted && date != null) {
                        setState(() {
                          _start = date;
                          _link = null;
                        });
                      }
                    },
              child: Text('連携開始月　${_start.year}年${_start.month}月'),
            ),
            const SizedBox(height: 12),
            if (_error != null) Text(_error!),
            if (_link == null)
              FilledButton(
                onPressed: _busy ? null : _prepare,
                child: const Text('招待リンクを発行'),
              )
            else ...[
              const Text('招待リンクを確認済みの連絡先から代表者本人に渡してください。有効期限は24時間です。'),
              FilledButton(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: _link!));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('招待リンクをコピーしました。')),
                    );
                  }
                },
                child: const Text('招待リンクをコピー'),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class TradeCompanyInvitationAcceptancePage extends StatefulWidget {
  const TradeCompanyInvitationAcceptancePage({
    super.key,
    required this.client,
    required this.code,
    required this.onDone,
    required this.title,
    this.onOpenDirectory,
  });
  final SupabaseClient client;
  final String code;
  final VoidCallback onDone;
  final String title;
  final VoidCallback? onOpenDirectory;

  @override
  State<TradeCompanyInvitationAcceptancePage> createState() =>
      _TradeCompanyInvitationAcceptancePageState();
}

class _TradeCompanyInvitationAcceptancePageState
    extends State<TradeCompanyInvitationAcceptancePage> {
  Map? _invite;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool accept = false}) async {
    final actor = widget.client.auth.currentUser?.id;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await widget.client.rpc(
        'trade_company_invitation',
        params: {'p_code': widget.code, 'p_accept': accept},
      );
      if (mounted && actor == widget.client.auth.currentUser?.id) {
        setState(() => _invite = data as Map);
      }
    } on PostgrestException catch (error) {
      if (mounted) {
        setState(
          () => _error = error.message.startsWith('会社')
              ? error.message
              : '招待を確認できません。招待された番号のアカウントと有効期限をご確認ください。',
        );
      }
    } catch (_) {
      if (mounted) setState(() => _error = '招待を確認できませんでした。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final invite = _invite;
    final accepted = invite?['accepted'] == true;
    final senderIsCustomer = invite?['local_role'] == 'customer';
    final senderRole = senderIsCustomer ? '取引会社' : '協力会社';
    final receiverRole = senderIsCustomer ? '協力会社' : '取引会社';
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (_busy) const LinearProgressIndicator(),
              if (_error != null) Text(_error!),
              if (invite != null) ...[
                Text(
                  accepted ? '連携が完了しました' : '④ 会社の関係を確認',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Text('招待元　${invite['sender']}'),
                Text('自社　${invite['receiver']}'),
                Text('自社から見た関係　$senderRole'),
                Text('連携開始月　${invite['start_month']}'),
                const SizedBox(height: 16),
                if (accepted)
                  Text(
                    '双方の「連携会社登録」に反映されました。自社では招待元が「$senderRole」、相手側では自社が「$receiverRole」と表示されます。',
                  )
                else
                  FilledButton(
                    onPressed: _busy ? null : () => _load(accept: true),
                    child: const Text('④ 承認して連携する'),
                  ),
              ] else if (!_busy)
                OutlinedButton(onPressed: _load, child: const Text('再確認')),
              if (accepted && widget.onOpenDirectory != null)
                OutlinedButton(
                  onPressed: _busy ? null : widget.onOpenDirectory,
                  child: const Text('連携会社登録を開く'),
                ),
              if (accepted && kIsWeb && !_busy)
                RegistrationCompletionActions(onContinue: widget.onDone)
              else if (accepted)
                FilledButton(
                  onPressed: _busy ? null : widget.onDone,
                  child: const Text('⑤ 完了して進む'),
                )
              else if (_error != null)
                TextButton(
                  onPressed: _busy ? null : widget.onDone,
                  child: const Text('招待を閉じる'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
