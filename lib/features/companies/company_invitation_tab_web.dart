import 'dart:js_interop';

const _key = 'sko_pending_company_invitation';

@JS('sessionStorage')
external _InvitationStorage get _storage;

extension type _InvitationStorage(JSObject _) implements JSObject {
  external JSString? getItem(JSString key);
  external void setItem(JSString key, JSString item);
  external void removeItem(JSString key);
}

String? readCompanyInvitationTab() {
  try {
    return _storage.getItem(_key.toJS)?.toDart;
  } catch (_) {
    return null;
  }
}

void writeCompanyInvitationTab(String? fragment) {
  try {
    if (fragment == null) {
      _storage.removeItem(_key.toJS);
    } else {
      _storage.setItem(_key.toJS, fragment.toJS);
    }
  } catch (_) {
    // The in-memory invite still works when browser storage is disabled.
  }
}
