import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'resident_tax_reminder_repository.dart';

/// Company-wide reminders are independent of annual tax amount saves.
class ResidentTaxReminderPanel extends StatefulWidget {
  const ResidentTaxReminderPanel({super.key, required this.companyId, this.repository});
  final String companyId;
  final ResidentTaxReminderRepository? repository;
  @override State<ResidentTaxReminderPanel> createState() => _ResidentTaxReminderPanelState();
}
class _ResidentTaxReminderPanelState extends State<ResidentTaxReminderPanel> {
  ResidentTaxReminderRepository? _repository;
  ResidentTaxReminderSettings? _settings;
  StreamSubscription<String?>? _subscription;
  String? _actor, _error;
  bool _busy = false, _invalid = false, _unavailable = false;
  int _generation = 0;
  @override void initState() {super.initState();_attach();}
  void _attach() {
    _repository = widget.repository ?? SupabaseResidentTaxReminderRepository.maybeCreate();
    _actor = _repository?.actorId;
    _subscription = _repository?.actorChanges.listen((actor) {
      if (actor != _actor && mounted) setState(() {_invalid = true;_settings = null;_generation++;_busy = false;});
    }, onError: (Object _) {if (mounted) setState(() {_invalid = true;_settings = null;_generation++;_busy = false;});});
    _read();
  }
  @override void didUpdateWidget(covariant ResidentTaxReminderPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.companyId != widget.companyId || oldWidget.repository != widget.repository) {
      _generation++;_settings = null;_error = null;_busy = false;_unavailable = false;
      // Company ABA must never restore a result from an earlier company load.
      if (!_invalid) {_subscription?.cancel();_attach();}
    }
  }
  bool _current(int generation, String company, String? actor) => mounted && !_invalid && generation == _generation &&
    widget.companyId == company && _repository?.actorId == actor;
  Future<void> _read() async {
    final repository = _repository;
    if (repository == null || _actor == null || _invalid) {_unavailable = true;return;}
    final generation = ++_generation, company = widget.companyId, actor = _actor;
    _busy = true;
    try {
      final result = await repository.read(company);
      if (_current(generation, company, actor)) setState(() {_settings = result;_error = null;_unavailable = false;});
    } catch (error) {
      if (_current(generation, company, actor)) {setState(() {
        _unavailable = error is PostgrestException && error.code == 'PGRST202';
        _error = _unavailable ? null : '通知設定を確認できません。再読み込みしてください。';
      });}
    } finally {if (_current(generation, company, actor)) setState(() {_busy = false;});}
  }
  Future<void> _save(bool value) async {
    final repository = _repository, settings = _settings;
    if (_busy || _invalid || repository == null || settings == null || !settings.canEdit) return;
    final generation = ++_generation, company = widget.companyId, actor = _actor;
    setState(() {_busy = true;_error = null;});
    try {
      final result = await repository.save(settings, value);
      if (_current(generation, company, actor)) setState(() {_settings = result;});
    } catch (_) {
      if (_current(generation, company, actor)) setState(() {_settings = null;_error = '保存状態を確認できません。再読み込みしてから変更してください。';});
    } finally {if (_current(generation, company, actor)) setState(() {_busy = false;});}
  }
  @override void dispose() {_generation++;_subscription?.cancel();super.dispose();}
  @override Widget build(BuildContext context) => Card(child: ExpansionTile(
    title: const Text('住民税の切替通知（会社共通）'),
    subtitle: const Text('管理者・給与閲覧権限のある方／5月1日・25日'),
    children: [Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('通知書が届いたら、全員の住民税を一括更新・確認してください。全員の年度確認が完了すると、要対応の通知は更新確認済みになり、1週間前の再通知は止まります。通知書が未着でもエラーではありません。'),
      if (_invalid) const Text('ログイン状態が変わりました。画面を開き直してください。')
      else if (_unavailable) const Text('通知機能は準備中です。通知はOFFのままです。住民税の入力・保存は続けられます。')
      else if (_settings != null) SwitchListTile(contentPadding: EdgeInsets.zero,
        title: const Text('切替通知を受け取る（会社共通）'),value: _settings!.enabled,
        subtitle: _settings!.canEdit ? null : const Text('会社管理者のみ変更できます'),
        onChanged: _busy || !_settings!.canEdit ? null : _save),
      if (_busy) const LinearProgressIndicator(),
      if (_error != null) Text(_error!),
      if (!_busy && !_invalid && (_error != null || _unavailable)) TextButton(onPressed: _read, child: const Text('再読み込み')),
    ]))],
  ));
}
