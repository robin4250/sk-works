# Registered Apple login — review-only candidate

Issue #273. This candidate is default OFF and is not deployed or connected to the Flutter login screen. Existing Google login and Apple-link prerequisites remain unchanged.

The broker verifies Apple's RS256 signature, issuer, allowlisted audience, nonce, expiry and recent issuance. Before asking GoTrue for a session it resolves an already registered Apple subject, consumes its token hash once, and snapshots the exact UID, company memberships and Google identities. After exchange, server `getUser` and a fresh snapshot must match. Failure after a session is returned revokes only that new session. An exchange whose network outcome is unknown cannot be rolled back by this adapter; it returns no credentials.

The SQL is review-only, service-only, default OFF, and writes only private rollout/replay bookkeeping. It does not create/link accounts or edit memberships. The Node tests use real generated RSA signatures with synthetic identities, and the PostgreSQL fixture is synthetic. Neither proves an actual Apple/GoTrue/native login.

Remaining before activation:

- Review the SQL against current Auth schema and grants, run the Native fixture, and review server/edge rate limits and replay-row retention. There is no deployment instruction in this candidate.
- Verify Apple Developer App ID / Services ID / audiences, key expiration, native entitlement, Supabase Apple provider, manual linking and callback allowlist. Never commit keys or client secrets.
- Implement nonce-capable native credential acquisition and Flutter session adoption with actor/history checks; no native package or signing configuration is changed here.
- Supply a recent same-session Google operation proof for adding Apple to an existing long-lived Google session. Do not weaken the existing 300-second AMR gate or require a logout that could lose context.
- Review direct GoTrue access: this broker prevents unknown subjects from reaching its own exchange, but cannot stop callers bypassing it. Supabase automatic email linking can still occur outside this route. A before-user-created hook blocks new accounts only, not automatic linking to an existing same-email account. This candidate is not a complete global no-link policy. The subject lookup and GoTrue exchange are also separate transactions: a concurrent unlink/delete can invalidate the precheck before exchange. A postcheck and local logout cannot undo a new Auth user/identity side effect. Activation therefore requires a server-enforced registration/linking policy covering this race, or a proven Auth-side primitive; this candidate alone must not be enabled.

`handler.mjs` accepts only `id_token` and `nonce`. The environment requires a server service-role JWT, a public Supabase key, the exact project origin, an explicit audience allowlist and explicit enable flag. No environment values or credential material are logged. Client callers receive only a generic Japanese failure message. SMS is unrelated and phone login remains preparation-only.

Validation: `node --test existing_apple_login.test.mjs`. The GitHub workflow also creates a disposable PostgreSQL 17 instance and executes `native.sql`; no production connection is used.

Further OFF preparation is in `google-primary-port-contract.md`: Google primary verification with real RSA tests, trusted read-only network adapters and a default-OFF Flutter native-credential adapter. The generic operation-proof protocol and public handler remain unchanged; fresh Google authentication acquisition, trusted challenge lifecycle, native channel registration and safe Apple activation remain incomplete.
