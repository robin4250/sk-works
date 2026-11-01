import 'package:flutter/material.dart';

/// This dialog collects primary credentials for a server proof. Native
/// biometrics and local unlock state are never submitted as proof.
class MasterFeatureProofDialog extends StatefulWidget {
  const MasterFeatureProofDialog({super.key, required this.expectedActor,
    required this.currentActor, required this.requestProof,
    required this.label, required this.enabled, this.title, this.description, this.confirmLabel});
  final String expectedActor;
  final String? Function() currentActor;
  final Future<String> Function(String password) requestProof;
  final String label;
  final bool enabled;
  final String? title, description, confirmLabel;
  @override
  State<MasterFeatureProofDialog> createState() => _ProofState();
}
class _ProofState extends State<MasterFeatureProofDialog> with WidgetsBindingObserver {
  final _password = TextEditingController();
  bool _busy = false;
  bool _returned = false;
  int _generation = 0;
  String? _error;
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;
  @override
  void initState() {
    super.initState();
    _lifecycle = WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    if (state != AppLifecycleState.resumed) {
      _generation++;_password.clear();
      if (mounted) setState(() => _error = '本人確認からやり直してください。');
    }
  }
  Future<void> _verify() async {
    if (_busy || _returned || _lifecycle != AppLifecycleState.resumed) return;
    if (widget.currentActor() != widget.expectedActor || _password.text.isEmpty) {
      setState(() => _error = 'ログイン状態と本パスワードを確認してください。');
      return;
    }
    final password = _password.text;
    _password.clear();
    final generation = ++_generation;
    setState(() {_busy = true;_error = null;});
    try {
      final proof = await widget.requestProof(password);
      if (!mounted || generation != _generation) return;
      if (widget.currentActor() != widget.expectedActor || _lifecycle != AppLifecycleState.resumed) {
        setState(() => _error = 'ログイン状態が変わりました。本人確認をやり直してください。');
        return;
      }
      // Nonce returned once to this exact requested operation, never persisted.
      setState(() {_returned = true;_busy = false;});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (generation != _generation ||
            widget.currentActor() != widget.expectedActor ||
            _lifecycle != AppLifecycleState.resumed ||
            ModalRoute.of(context)?.isCurrent != true) {
          // The credential response and this frame are separate async turns.
          // Discard the nonce if anything changed between them, and permit a
          // fresh verification after returning to the original account/app.
          _generation++;
          _password.clear();
          setState(() {
            _returned = false;
            _busy = false;
            _error = 'ログイン状態が変わりました。本人確認をやり直してください。';
          });
          return;
        }
        Navigator.of(context).pop(proof);
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = '本パスワードで本人確認できませんでした。もう一度お試しください。');
      }
    } finally {
      if (mounted && !_returned) setState(() => _busy = false);
    }
  }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);_generation++;
    _password.clear();_password.dispose();super.dispose();
  }
  @override
  Widget build(BuildContext context) => PopScope(canPop: !_busy,
    child: AlertDialog(
      title: Text(widget.title ?? (widget.enabled ? '機能を有効にする' : '機能を一時停止する')),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(widget.description ?? '「${widget.label}」を${widget.enabled ? '有効' : '一時停止'}にします。ログイン用の本パスワードで本人確認してください。'),
        const SizedBox(height: 12),
        TextField(key: const Key('master-feature-password'), controller: _password,
          enabled: !_busy && !_returned, obscureText: true, autocorrect: false, enableSuggestions: false,
          decoration: const InputDecoration(labelText: 'ログイン用の本パスワード'),
          onSubmitted: (_) => _verify()),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!)),
      ])),
      actions: [TextButton(onPressed: _busy || _returned ? null : () => Navigator.pop(context), child: const Text('キャンセル')),
        FilledButton(onPressed: _busy || _returned ? null : _verify, child: Text(widget.confirmLabel ?? '本人確認して変更'))],
    ));
}
