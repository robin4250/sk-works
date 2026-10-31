# Company-scoped package classification — source-only follow-up

Frozen PR1700 and PR1702 are not edited. This follow-up narrows the pending compatibility proposal's pair rejection to immutable packages whose sender or recipient equals the already authenticated p_company. Foreign-only package IDs therefore reach the same legacy generic denial as nonexistent or foreign legacy items, rather than a distinguishable dedicated error. Authorized own-party packages still require the dedicated order path.

The regression first failed against the frozen proposal at `foreign package indistinguishable from unknown`. After the one-predicate change, local PGlite passes 83 assertions: foreign package/nonexistent/foreign legacy errors match code and message, foreign package/item/inbox rows are unchanged, and all prior ten own-party caller boundaries remain intact. Existing supported data, attributes, ACLs, original helper/Auth/C source, RLS, package ownership immutability, and the exact installer's lock handling remain unchanged.

The generated `consumer-boundary.sql.review-only` here supersedes that file from PR1700 for a future separately approved installer. Do not apply both versions sequentially: both deliberately expect the original production CHECK and consumer definitions. This is not a production upgrade of already-used data and never changes live objects. Orders remain OFF and production HOLD remains.

Native/CI and independent completed-log review are pending. Production schema/Auth, actual sender concurrency, hosted deployment, real partner delivery and iPhone behavior remain separate unproved conditions.
