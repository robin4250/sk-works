# Panel eleven — isolated normal device addition contract

Review-only, unconnected and default OFF. This is not a completed tablet feature.
Base c9fe3dd8b328966686a980d009315b52a7d65761. No production changes.

## Purpose and boundaries

An already trusted iPhone should authorize a second device logged into the same
existing user. This is distinct from first-time bootstrap, emergency dual-email
recovery and the two-factor requirement at Master entry. No existing device is
locked, revoked, deleted, re-keyed or overwritten. No account, provider identity,
company membership, role, password or shared second credential is created/changed.

New candidate file/table/API names use neutral `panel_eleven` naming. This naming
is not an authorization control. Existing APIs are not renamed.

## Contract

The target device authenticates normally to the existing user and requests a
120-second addition using a newly generated device key. The server stores only
key/nonce digests in the request and binds it to that exact live target session.
An already registered key (including locked or revoked history) is rejected;
there is no UPSERT or rebootstrap path.

The source must be the same enabled Master on another live session, presenting
an existing unlocked/unrevoked trusted device key. A service-only issuer seam
binds a 120-second single-use proof to owner, source session, source device,
request ID and exact target-key digest. The ordinary source approval RPC consumes
that exact proof atomically. Client Face ID booleans, arbitrary nonce strings,
company roles and normal authenticated callers cannot issue the proof.

The target completes only with the original target session, key and nonce after
approval. Completion rechecks both sessions and source trust, takes the Master
owner row before the request/device rows, INSERTs one new device and consumes the
request. Duplicate/concurrent completion cannot register twice. Existing iPhone
fields and identity/company/role/credential records remain unchanged.

READ COMMITTED is the supported transaction isolation; others fail closed.
The fixture uses disposable loopback PostgreSQL 17 and synthetic sessions/proofs.
It does not authenticate a real Google account or invoke native biometrics.

## Critical missing integration — do not enable

The service-only issuer is an integration seam, not a provider verifier. Existing
`reauthenticate-operation/handler.mjs` uses a primary password grant, so it cannot
be declared compatible with the current Google-only owner. No password is forced
onto that account. Existing Google login uses SDK PKCE plus `prompt=select_account`;
a new token/session or fresh `iat` alone does not prove fresh user authentication.

A possible reuse path is existing Google PKCE with a server-issued request nonce
and a requested Google `auth_time` claim, then server signature/issuer/audience,
nonce, authentication-age and immutable Google subject checks against the existing
Google identity and exact source/target operation. Google's official OIDC docs
state `auth_time` is conditional on requested claims and enabled settings, and
`select_account` alone is an account chooser. Provider settings, GoTrue parameter
forwarding, ID-token availability and real fresh-auth behavior are unverified.
Missing proof must deny; the candidate has no Face-only or shared-password-only
fallback and never interprets refresh or linking as fresh authentication.

Reference: https://developers.google.com/identity/openid-connect/openid-connect
Reference: https://supabase.com/docs/guides/auth/password-security

Before production activation: implement and independently validate this fresh
provider proof, replay and wrong-subject/nonce/audience cases, lifecycle/session
invalidation, source device confirmation UI and target QR/deep-link binding;
provide operation receipts for uncertain network outcomes, capacity/rate limits,
retention and secret-safe logging, protected actual backup/isolated restore and
specific production approval. UI routes/repository wiring and physical tablet
installation/login remain incomplete. Existing dual-email recovery stays intact
and is not used as an ordinary device-addition workaround.
