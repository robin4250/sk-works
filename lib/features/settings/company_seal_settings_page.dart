import 'package:flutter/material.dart';

import '../../international/language_controller.dart';
import '../people/company_submitted_document_repository.dart';

class CompanySealSettingsPage extends StatefulWidget {
  const CompanySealSettingsPage({super.key});

  @override
  State<CompanySealSettingsPage> createState() => _CompanySealSettingsPageState();
}

class _CompanySealSettingsPageState extends State<CompanySealSettingsPage> {
  final _repository = CompanySubmittedDocumentRepository.maybeCreate();
  bool? _enabled;
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final repository = _repository;
      if (repository == null) throw StateError('会社設定を利用できません。');
      final enabled = await repository.loadCompanySealEnabled();
      if (!mounted) return;
      setState(() {
        _enabled = enabled;
        _error = null;
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = '会社角印の設定を読み込めませんでした。';
        _busy = false;
      });
    }
  }

  Future<void> _save(bool enabled) async {
    if (_busy || _enabled == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final saved = await _repository!.saveCompanySealEnabled(enabled);
      if (!mounted) return;
      setState(() {
        _enabled = saved;
        _busy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(SkoLanguageController.tr('会社角印の設定を保存しました'))),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = '会社角印の設定を保存できませんでした。';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    return Scaffold(
      appBar: AppBar(title: Text(SkoLanguageController.tr('会社角印'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(SkoLanguageController.tr('会社共通。請求書・給与明細・支払証明書に反映します。')),
          const SizedBox(height: 12),
          if (_busy) const LinearProgressIndicator(),
          if (_enabled != null)
            SwitchListTile(
              title: Text(SkoLanguageController.tr('会社角印を表示')),
              value: _enabled!,
              onChanged: _busy ? null : _save,
            ),
          Text(SkoLanguageController.tr('OFFでも確認印・承認印と承認履歴は残ります。')),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              SkoLanguageController.tr(_error!),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            TextButton(
              onPressed: _busy ? null : _load,
              child: Text(SkoLanguageController.tr('再読み込み')),
            ),
          ],
        ],
      ),
    );
  }
}
