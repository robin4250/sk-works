import 'dart:async';
import 'package:flutter/material.dart';
import '../../data/supabase_backend.dart';
import 'trade_document_template_payload.dart';

class TradeDocumentTemplateSettingsButton extends StatelessWidget {
  const TradeDocumentTemplateSettingsButton({super.key, required this.subjectKind});
  final String subjectKind;
  @override Widget build(BuildContext context) => ListTile(
    leading: const Icon(Icons.description_outlined),
    title: Text(subjectKind == 'invoice' ? '注文請書の設定' : '注文書の設定'),
    onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) =>
      TradeDocumentTemplateSettingsPage(subjectKind: subjectKind))));
}
class TradeDocumentTemplateSettingsPage extends StatelessWidget {
  const TradeDocumentTemplateSettingsPage({super.key, required this.subjectKind});
  final String subjectKind;
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(subjectKind == 'invoice' ? '注文請書の設定' : '注文書の設定')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      TradeDocumentTemplateSettingsSection(subjectKind: subjectKind),
    ]));
}

/// Same inline configuration in invoice and payment-certificate settings.
/// Never writes a financial document or replaces a saved appendix.
class TradeDocumentTemplateSettingsSection extends StatefulWidget {
  const TradeDocumentTemplateSettingsSection({super.key, required this.subjectKind});
  final String subjectKind;
  @override State<TradeDocumentTemplateSettingsSection> createState() => _SectionState();
}
class _SectionState extends State<TradeDocumentTemplateSettingsSection> with WidgetsBindingObserver {
  final _fields = <String, TextEditingController>{};
  String? _company, _actor, _token, _error;
  StreamSubscription<dynamic>? _auth;
  int _version = 0;
  bool _ready = false, _saving = false, _revoked = false, _canManage = false;
  bool _enhanced = false, _automatic = true;
  bool get _invoice => widget.subjectKind == 'invoice';
  bool get _same => !_revoked && SupabaseBackend.isInitialized &&
    SupabaseBackend.client.auth.currentUser?.id == _actor &&
    SupabaseBackend.client.auth.currentSession?.accessToken == _token;
  @override void initState() { super.initState(); WidgetsBinding.instance.addObserver(this); _load(); }
  void _revoke() { if (mounted && !_revoked) setState(() { _revoked = true; _canManage = false; }); }
  @override void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _revoke();
  }
  Future<void> _load() async {
    try {
      if (!SupabaseBackend.isInitialized) throw StateError('ログインが必要です。');
      final c = SupabaseBackend.client;
      _actor = c.auth.currentUser?.id; _token = c.auth.currentSession?.accessToken;
      if (_actor == null || _token == null) throw StateError('ログインが必要です。');
      _auth = c.auth.onAuthStateChange.listen((_) { if (!_same) _revoke(); }, onError: (_) => _revoke(), onDone: _revoke);
      final rows = await c.from('company_members').select('company_id').eq('user_id', _actor!)
          .setHeader('Authorization', 'Bearer $_token');
      if (!_same || !mounted) return;
      if (rows.length != 1) throw StateError('対象の会社を一意に確認できません。');
      _company = rows.single['company_id'].toString();
      final raw = await c.rpc('trade_document_template', params: {
        'p_kind': widget.subjectKind, 'p_company': _company,
      }).setHeader('Authorization', 'Bearer $_token');
      if (!_same || !mounted) return;
      if (raw is! Map || raw['payload'] is! Map || raw['version'] is! int) {
        throw StateError('設定を確認できません。');
      }
      final payload = raw['payload'] as Map;
      const defaults = <String, String>{
        'work_name': '', 'work_address': '',
        'intro_text': '発注者（以下「甲」という）は、受注者（以下「乙」という）に対し、下記の通り工事を発注します。',
        'acceptance_text': '乙は、貴殿から受領した{order_date}付の注文書記載の条件通り、本工事を請け負うことを承諾いたします。',
        'payment_conditions': '工事完了確認後、乙の指定口座に振り込む。', 'notes': '',
      };
      for (final entry in defaults.entries) {
        _fields[entry.key] = TextEditingController(text: payload[entry.key]?.toString() ?? entry.value);
      }
      setState(() {
        _version = raw['version'] as int; _canManage = raw['can_manage'] == true;
        _enhanced = raw['settings_contract_version'] == 2;
        _automatic = payload['auto_generate'] != false; _ready = true;
      });
    } catch (e) { if (mounted) setState(() => _error = e.toString()); }
  }
  Future<void> _save() async {
    if (!_same || !_canManage || _saving) return;
    setState(() { _saving = true; _error = null; });
    try {
      final payload = <String, dynamic>{...tradeDocumentTemplatePayload({
        for (final entry in _fields.entries)
          if (_enhanced || !_invoice || !{'work_name', 'work_address'}.contains(entry.key))
            entry.key: entry.value.text,
      })};
      if (_enhanced) {
        payload['auto_generate'] = _automatic;
        // Preserve explicit clearing instead of inheriting the order default.
        payload['work_name'] = _fields['work_name']!.text.trim();
        payload['work_address'] = _fields['work_address']!.text.trim();
      }
      final raw = await SupabaseBackend.client.rpc('trade_document_template', params: {
        'p_kind': widget.subjectKind, 'p_company': _company,
        'p_expected_version': _version, 'p_payload': payload,
      }).setHeader('Authorization', 'Bearer $_token');
      if (!_same || !mounted) return;
      if (raw is! Map || raw['version'] != _version + 1 || raw['payload'] is! Map) {
        throw StateError('保存結果を確認できません。設定を開き直してください。');
      }
      final fresh = await SupabaseBackend.client.rpc('trade_document_template', params: {
        'p_kind': widget.subjectKind, 'p_company': _company,
      }).setHeader('Authorization', 'Bearer $_token');
      if (!_same || !mounted) return;
      if (fresh is! Map || fresh['version'] != raw['version'] || fresh['payload'] is! Map ||
          payload.entries.any((entry) => (fresh['payload'] as Map)[entry.key] != entry.value)) {
        throw StateError('保存後の設定が変わりました。開き直して確認してください。');
      }
      setState(() { _version = fresh['version'] as int; _error = '設定を保存しました。新規生成分から反映します。'; });
    } catch (e) { if (mounted && _same) setState(() => _error = e.toString()); }
    finally { if (mounted) setState(() => _saving = false); }
  }
  @override void dispose() { WidgetsBinding.instance.removeObserver(this); _auth?.cancel(); for (final c in _fields.values) { c.dispose(); } super.dispose(); }
  @override Widget build(BuildContext context) => Card(child: Padding(
    padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(_invoice ? '注文請書の自動生成・初期文' : '注文書の自動生成・初期文', style: const TextStyle(fontWeight: FontWeight.w800)),
      ExpansionTile(title: const Text('？ 設定の反映範囲'), children: [Padding(padding: const EdgeInsets.all(8),
        child: Text(_invoice
          ? '工事名・工事場所は新規注文請書の初期文です。初回は注文書の同じ初期文を引き継ぎます。保存後は注文請書の設定を使用します。自動生成OFFでも保存済みの注文請書は保持します。各帳票の確認・編集はプレビュー内から行います。'
          : '工事名・工事場所は新規注文書の初期文です。自動生成OFFでも保存済みの注文書は保持します。設定変更で保存済み・確定済み帳票を上書きしません。単体生成は協力会社登録の会社詳細から利用できます。'))]),
      if (_revoked) const Text('ログイン状態や画面の状態が変わりました。設定を開き直してください。')
      else if (!_ready) Text(_error ?? '読み込み中…')
      else ...[
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('新規帳票に自動生成する'),
          value: _automatic, onChanged: _canManage && _enhanced && !_saving ? (v) => setState(() => _automatic = v) : null),
        if (!_enhanced) const Text('自動生成の切替と注文請書の工事初期文は、設定機能の更新後に利用できます。'),
        for (final key in ['work_name', 'work_address', if (_invoice) 'acceptance_text' else ...['intro_text', 'payment_conditions'], 'notes'])
          Padding(padding: const EdgeInsets.only(bottom: 10), child: TextField(controller: _fields[key],
            enabled: _canManage && !_saving && (_enhanced || !_invoice || !{'work_name', 'work_address'}.contains(key)),
            maxLines: key == 'work_name' ? 1 : 3,
            maxLength: key == 'notes' ? 600 : {'work_name', 'work_address'}.contains(key) ? 240 : 400,
            decoration: InputDecoration(labelText: const {'work_name': '工事名の初期文', 'work_address': '工事場所の初期文',
              'acceptance_text': '承諾文（{order_date}を注文書日に置換）', 'intro_text': '注文書の冒頭文', 'payment_conditions': '支払条件', 'notes': 'その他特記事項'}[key]))),
        if (_error != null) Text(_error!),
        FilledButton(onPressed: _canManage && !_saving ? _save : null, child: Text(_saving ? '保存中…' : '初期文・自動生成設定を保存')),
      ],
    ])));
}
