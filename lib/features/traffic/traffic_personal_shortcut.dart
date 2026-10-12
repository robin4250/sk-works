import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../international/language_controller.dart';
import 'traffic_shortcut_store.dart';

class TrafficPersonalShortcut extends StatefulWidget {
  const TrafficPersonalShortcut({super.key, required this.scope, this.store, this.canOpen, this.open});
  final TrafficShortcutScope? scope;
  final TrafficShortcutStore? store;
  final Future<bool> Function(Uri)? canOpen;
  final Future<bool> Function(Uri)? open;
  @override
  State<TrafficPersonalShortcut> createState() => _TrafficPersonalShortcutState();
}

class _TrafficPersonalShortcutState extends State<TrafficPersonalShortcut> {
  final _deviceStore = DeviceTrafficShortcutStore();
  TrafficShortcut? _shortcut;
  bool _busy = false;
  int _generation = 0;
  BuildContext? _dialogContext;
  TrafficShortcutStore get _store => widget.store ?? _deviceStore;
  bool _current(TrafficShortcutScope scope, int generation) => mounted && widget.scope == scope && _generation == generation;
  @override
  void initState() { super.initState(); _load(); }
  @override
  void didUpdateWidget(TrafficPersonalShortcut oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scope != widget.scope || oldWidget.store != widget.store) { _dismissEditor(); _load(); }
  }
  void _dismissEditor() {
    final dialogContext = _dialogContext;
    _dialogContext = null;
    if (dialogContext == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!dialogContext.mounted) return;
      final route = ModalRoute.of(dialogContext);
      if (route != null && route.isActive) Navigator.of(dialogContext).removeRoute(route);
    });
  }
  @override
  void dispose() { _generation++; _dismissEditor(); super.dispose(); }
  Future<void> _load() async {
    final generation = ++_generation;
    final scope = widget.scope;
    _shortcut = null;
    _busy = scope?.valid ?? false;
    if (scope == null || !scope.valid) return;
    try {
      final result = await _store.load(scope);
      if (_current(scope, generation)) setState(() { _shortcut = result; _busy = false; });
    } catch (_) {
      if (_current(scope, generation)) { setState(() => _busy = false); _error('追加した項目を取得できませんでした。'); }
    }
  }
  void _error(String message, {bool edit = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(SkoLanguageController.tr(message)),
      action: edit ? SnackBarAction(label: SkoLanguageController.tr('編集'), onPressed: _edit) : null,
    ));
  }
  Future<void> _launch() async {
    if (_busy) return;
    if (_shortcut == null) { await _edit(); return; }
    final scope = widget.scope;
    if (scope == null || !scope.valid) return;
    final generation = _generation;
    final shortcut = _shortcut!;
    setState(() => _busy = true);
    var opened = false;
    try {
      final available = shortcut.kind == TrafficShortcutKind.web || await (widget.canOpen?.call(shortcut.uri) ?? canLaunchUrl(shortcut.uri));
      if (available && _current(scope, generation)) {
        opened = await (widget.open?.call(shortcut.uri) ?? launchUrl(shortcut.uri, mode: LaunchMode.externalApplication));
      }
    } catch (_) { opened = false; }
    if (!_current(scope, generation)) return;
    setState(() => _busy = false);
    if (!opened) _error('登録した項目を開けませんでした。編集して選び直してください。', edit: true);
  }
  Future<void> _edit() async {
    if (_busy) return;
    final scope = widget.scope;
    if (scope == null || !scope.valid) return;
    final generation = _generation;
    setState(() => _busy = true);
    var googleAvailable = false;
    try { googleAvailable = await (widget.canOpen?.call(Uri.parse('comgooglemaps://')) ?? canLaunchUrl(Uri.parse('comgooglemaps://'))); } catch (_) { /* Unavailable candidates stay hidden. */ }
    if (!mounted || !_current(scope, generation)) return;
    final selection = await showDialog<String>(context: context, builder: (context) {
      _dialogContext = context;
      return SimpleDialog(
      title: Text(SkoLanguageController.tr('追加する項目')),
      children: [
        Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: Text(SkoLanguageController.tr('対応アプリのうち、この端末で開けるものを表示します。Webサイトも登録できます。'))),
        if (googleAvailable) SimpleDialogOption(onPressed: () => Navigator.pop(context, 'googleMaps'), child: Text(SkoLanguageController.tr('Googleマップ'))),
        SimpleDialogOption(onPressed: () => Navigator.pop(context, 'web'), child: Text(SkoLanguageController.tr('Webサイトを登録'))),
        if (_shortcut != null) SimpleDialogOption(onPressed: () => Navigator.pop(context, 'remove'), child: Text(SkoLanguageController.tr('登録を解除'))),
        SimpleDialogOption(onPressed: () => Navigator.pop(context), child: Text(SkoLanguageController.tr('閉じる'))),
      ],
    ); });
    _dialogContext = null;
    if (!mounted || !_current(scope, generation)) return;
    TrafficShortcut? next;
    if (selection == 'googleMaps') next = const TrafficShortcut.googleMaps();
    if (selection == 'web') {
      next = await showDialog<TrafficShortcut>(context: context, builder: (context) { _dialogContext = context; return _WebShortcutDialog(initial: _shortcut); });
      _dialogContext = null;
      if (!_current(scope, generation)) return;
    }
    if (selection == null || (selection == 'web' && next == null)) { setState(() => _busy = false); return; }
    try {
      await _store.save(scope, next);
      if (_current(scope, generation)) setState(() { _shortcut = next; _busy = false; });
    } catch (_) {
      if (_current(scope, generation)) { setState(() => _busy = false); _error('追加した項目を保存できませんでした。'); }
    }
  }
  @override
  Widget build(BuildContext context) {
    final ready = !_busy && (widget.scope?.valid ?? false);
    return Tooltip(
      message: _shortcut == null ? SkoLanguageController.tr('追加する項目') : '${_shortcut!.label}：${SkoLanguageController.tr('長押しで編集・解除')}',
      child: TextButton(
        key: const ValueKey('traffic-personal-shortcut'),
        onPressed: ready ? _launch : null,
        onLongPress: ready && _shortcut != null ? _edit : null,
        style: TextButton.styleFrom(minimumSize: const Size(44, 44), padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4)),
        child: Row(children: [
          Icon(_shortcut == null ? Icons.add : _shortcut!.kind == TrafficShortcutKind.web ? Icons.link : Icons.map_outlined, size: 16),
          const SizedBox(width: 2),
          Expanded(child: Text(_shortcut == null ? SkoLanguageController.tr('追加') : _shortcut!.kind == TrafficShortcutKind.googleMaps ? SkoLanguageController.tr(_shortcut!.label) : _shortcut!.label,
            maxLines: 2, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10, height: 1.15))),
        ]),
      ),
    );
  }
}

class _WebShortcutDialog extends StatefulWidget {
  const _WebShortcutDialog({this.initial});
  final TrafficShortcut? initial;
  @override
  State<_WebShortcutDialog> createState() => _WebShortcutDialogState();
}
class _WebShortcutDialogState extends State<_WebShortcutDialog> {
  late final _name = TextEditingController(text: widget.initial?.kind == TrafficShortcutKind.web ? widget.initial!.label : '');
  late final _url = TextEditingController(text: widget.initial?.webUrl?.toString() ?? '');
  final _form = GlobalKey<FormState>();
  @override
  void dispose() { _name.dispose(); _url.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(SkoLanguageController.tr('Webサイトを登録')),
    content: SingleChildScrollView(child: Form(key: _form, child: Column(mainAxisSize: MainAxisSize.min, children: [
      TextFormField(key: const ValueKey('traffic-web-name'), controller: _name, maxLength: 30,
        decoration: InputDecoration(labelText: SkoLanguageController.tr('表示名')),
        validator: (value) => value?.trim().isNotEmpty == true ? null : SkoLanguageController.tr('表示名を入力してください。')),
      TextFormField(key: const ValueKey('traffic-web-url'), controller: _url, keyboardType: TextInputType.url,
        autocorrect: false, decoration: const InputDecoration(labelText: 'https://'),
        validator: (_) => TrafficShortcut.web(_name.text, _url.text) == null ? SkoLanguageController.tr('https://で始まるURLを入力してください。') : null),
    ]))),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: Text(SkoLanguageController.tr('閉じる'))),
      TextButton(onPressed: () { if (_form.currentState!.validate()) Navigator.pop(context, TrafficShortcut.web(_name.text, _url.text)); }, child: Text(SkoLanguageController.tr('登録'))),
    ],
  );
}
