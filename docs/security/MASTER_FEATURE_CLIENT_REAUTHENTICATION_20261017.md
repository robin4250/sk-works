# Existing Master feature switches: client step-up connection

The existing vehicle, route and three traffic switches retain their labels,
confirmation, saved values and reversibility. Their mutation now discovers the
existing `reauthentication_capabilities.master_feature` contract. Explicit OFF or
only PGRST202 (missing capability API) keeps the existing setter. Permission,
network and malformed capability responses fail closed. ON requires a primary
password proof for `master.feature.set` with exact `{feature_key, enabled}` and
calls only `set_master_feature_enabled_with_proof`; failure never retries the
legacy setter. These server routines already exist in the staged foundation.

The request carries the captured original session bearer to avoid dispatching an
old form under a different account during the SDK asynchronous token lookup.
Actor changes and stale async results are rejected. Background cancels only this
page's owned confirmation/proof dialog and invalidates its work; resuming reloads
current flags and requires new confirmation/password/proof. A stale response or
finally callback cannot overwrite a later operation. Password input clears on
submission, background and disposal. Strings/pending HTTP cannot be guaranteed
zeroed or physically cancelled; an already sent mutation may have completed and
is reconciled through a fresh server read, never automatically replayed.

LINE/referral/weather panels keep their existing implementations and State during
normal background/resume with successful reload. They are separate APIs and are
not newly protected by this switch-specific step-up. Existing device lock,
bootstrap, dual-code recovery, sign-in providers, IDs/roles/company associations,
Auth/core code, SQL, Edge and production settings are unchanged.

The global server gate remains OFF and staged SQL is not applied. OAuth-only
users have no verified primary-password alternative: do not enable enforcement
until alternatives, confidential backup, isolated restore, normal-admin/UI
comparison, impact report and explicit user approval are complete.

New Widget tests cover ON/OFF, exact target, cancellation/failures/duplicate
callbacks, actor changes, background/late proof and post-frame interruption,
late save results, and existing panel State preservation. Locked SDK transport
tests cover five keys/both values, bearer/nonce, missing/invalid capability,
invalid targets and no downgrade. Existing server PostgreSQL/Edge tests remain
separate evidence. This is not a real device or production recovery/OAuth test.
