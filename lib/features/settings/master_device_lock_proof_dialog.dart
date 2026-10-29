import 'package:flutter/material.dart';

/// This dialog collects primary credentials for a server proof. Native
/// biometrics and local unlock state are never submitted as proof.
class MasterDeviceLockProofDialog extends StatefulWidget {
  const MasterDeviceLockProofDialog({super.key, required this.expectedActor,
    required this.currentActor, required this.requestProof,
    required this.deviceName, required this.locked, this.sessionCurrent});
  final bool Function()? sessionCurrent;
  bool get sessionIsCurrent => sessionCurrent?.call() ?? true;
  final String expectedActor;
  final String? Function() currentActor;
  final Future<String> Function(String password) requestProof;
  final String deviceName;
  final bool locked;
  @override
  State<MasterDeviceLockProofDialog> createState() => _ProofState();
}
class _ProofState extends State<MasterDeviceLockProofDialog> with WidgetsBindingObserver {
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
    if (!widget.sessionIsCurrent || widget.currentActor() != widget.expectedActor || _password.text.isEmpty) {
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
      if (!widget.sessionIsCurrent || widget.currentActor() != widget.expectedActor || _lifecycle != AppLifecycleState.resumed) {
        setState(() => _error = 'ログイン状態が変わりました。本人確認をやり直してください。');
        return;
      }
      // Nonce returned once to this exact requested operation, never persisted.
      setState(() {_returned = true;_busy = false;});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (generation != _generation ||
            !widget.sessionIsCurrent || widget.currentActor() != widget.expectedActor ||
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
      title: Text(widget.locked ? '端末をロック' : '端末のロックを解除'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('「${widget.deviceName}」の変更を行います。ログイン用の本パスワードで本人確認してください。'),
        const SizedBox(height: 12),
        TextField(key: const Key('master-device-lock-password'), controller: _password,
          enabled: !_busy && !_returned, obscureText: true, autocorrect: false, enableSuggestions: false,
          decoration: const InputDecoration(labelText: 'ログイン用の本パスワード'),
          onSubmitted: (_) => _verify()),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!)),
      ])),
      actions: [TextButton(onPressed: _busy || _returned ? null : () => Navigator.pop(context), child: const Text('キャンセル')),
        FilledButton(onPressed: _busy || _returned ? null : _verify, child: const Text('本人確認して変更'))],
    ));
}
