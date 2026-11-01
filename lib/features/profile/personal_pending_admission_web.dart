import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:crypto/crypto.dart';
@JS('navigator') external JSObject get _navigator;
@JS('isSecureContext') external bool get _secureContext;

/// Cooperative same-origin exclusion only. Not server admission or device trust.
Future<T> withPersonalPendingAdmission<T>(String actor, Future<T> Function() body) async {
  if (actor.isEmpty || actor.length > 128 || !_secureContext ||
      !_navigator.has('locks')) {
    throw StateError('このブラウザでは安全に保存できません。別の端末をご利用ください。');
  }
  // No raw UID, company, bank, DOB, session or token in browser-visible lock names.
  final name='sko.personal.pending.v1.${sha256.convert(utf8.encode('sko-personal-pending-v1:$actor'))}';
  T? value;
  Object? failure;
  StackTrace? failureStack;
  bool completed=false;
  final callback=((JSAny? lock) {
    return (() async {
      if (lock == null || lock.isUndefinedOrNull) {
        failure=StateError('別のタブで保存処理中です。結果を確認してから操作してください。');
        failureStack=StackTrace.current;
        return null;
      }
      // The JS promise covers the WHOLE Dart future, including unknown ACK fence.
      try { value=await body(); completed=true; }
      catch(error, stack) { failure=error; failureStack=stack; }
      return null;
    })().toJS;
  }).toJS;
  try {
    final manager=_navigator.getProperty<JSObject?>('locks'.toJS);
    if(manager==null)throw StateError('lock manager unavailable');
    await manager.callMethod<JSPromise<JSAny?>>(
      'request'.toJS,name.toJS,{'mode':'exclusive','ifAvailable':true}.jsify(),callback).toDart;
  } catch (_) {
    // A platform failure is never permission to retry a body that may have run.
    failure ??= StateError('保存処理の結果を確認できません。再送せず状況を確認してください。');
    failureStack ??= StackTrace.current;
  }
  if (failure != null) Error.throwWithStackTrace(failure!,failureStack!);
  if (!completed) throw StateError('保存処理の結果を確認できません。再送せず状況を確認してください。');
  return value as T;
}
