# Employee initial session: disposable Auth-hook integration prototype

Not a product migration, hosted hook, deployed issuer or completed QR-v2 fix.

This reuses the pinned CLI/GoTrue/PostgREST transport, freshness and credential-protection boundaries of PR #1245, without rerunning that unchanged baseline observation. It configures only a newly created local CLI fixture's official custom-access-token hook. Phone remains OFF; credentials are explicit synthetic email proxies, not real phone/QR proof.

The first real Auth password request observes whether the hook can see the exact `auth.sessions` row identified by GoTrue's server-generated `session_id`, and whether its user matches. If unavailable, it reports that prerequisite as unavailable and never presents the lease prototype as verified.

Only when that prerequisite holds, a disposable prototype connects the actual GoTrue hook to a private, explicitly enrolled synthetic invitation registry. It tests expiry/cancellation/repeated-password rejection before token issuance, one concurrent winner, binding to the actual session, a separate non-inheriting initial role, direct REST/RPC business denial, live lease checks for the onboarding allowlist, old-generation/expired/cancelled JWT denial, and a fresh permanent session after actual password replacement plus fixture approval.

Ordinary unregistered and pre-existing approved synthetic email users remain outside the registry and retain their original Auth behavior. This does not prove Google/Apple/Face ID external login, production company roles, Storage, all existing SECURITY DEFINER paths, or the real issuer.

## Missing before a coherent product implementation

- The real trusted `create-employee-invite` issuer does not enroll this registry; enrollment is fixture-only trusted SQL after Auth Admin creates fresh synthetic users.
- The real QR still contains a reusable password. Random one-use token redemption and hash storage are not implemented here.
- Lost Auth responses, bounded retry receipts, cancellation/reissue races and account recovery must be designed without permanently locking out legitimate users.
- Full onboarding RPC/Storage/Edge allowlist integration, all old-session cutoffs and approved-user/owner recovery must be reconciled with deployed definitions and tested before rollout.
- No hosted Auth hook/config/RLS/grant/data change occurs. This fixture must never be copied wholesale into production.

Official interfaces checked:

- https://supabase.com/docs/guides/auth/auth-hooks/custom-access-token-hook
- https://supabase.com/docs/guides/auth/auth-hooks/password-verification-hook

The password-verification hook provides `user_id`/`valid`, not an actual session ID or durable redemption operation ID. It cannot by itself establish this session boundary or safely implement a replay receipt.
