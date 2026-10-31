# Preserve the deployed session principal

READ ONLY pg_catalog verification (2026-10-30, business rows0, production writes0) found:

- `private.require_reauthentication_session()` source MD5 `b5c8e2f259a99b3c69694ad0640080e5` checks both the JWT `is_anonymous` claim and `auth.users.is_anonymous`.
- `private.account_access_allowed()` source MD5 `aeca25db212c043c472334026bd98724` does not read JWT metadata.

The Edge claim allowlist now retains `is_anonymous`; an explicitly anonymous verified JWT is rejected at HTTP authentication. This preserves the existing claim-based session policy as well as the DB user check. The existing DB anonymous-user rejection was present before this correction; no production exposure or live-user test is claimed.

The actual pinned-SDK ES256 fixture verifies anonymous refusal and retention of a false claim. Legacy claims without the field retain the existing SQL fallback. Editable `user_metadata` remains excluded; identity, live SID, exact membership and current write feature checks remain server-derived. No SQL/auth settings were changed or deployed.
