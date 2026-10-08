# Staged proxy checkout review

Base main a2a0ad26. Migration generated with Supabase CLI. No production application.

Private per-company rollout has no inserted rows and defaults false. No enable API is exposed. Every read/write RPC checks the gate, current account access, current membership, and an active personal clock-in anchor. Roster reads return only worker display names, source IDs, work dates and existing checkout times; no location/photo evidence is disclosed.

`evidence_origin=team_proxy` and `proxy_actor_user_id` explicitly identify proxy rows. `verification_mode=manual` is the technical mode because the existing nonmanual CHECK requires personal coordinates. These rows are not personal GPS/photo evidence. Existing rows keep both new columns NULL; no backfill/default is applied.

The origin trigger prohibits direct-client proxy inserts and origin rewrites. It assumes the migration/private function owner is postgres (the Supabase migration owner); verify ownership before rollout. The existing source-evidence guard and source unique index continue to enforce scope, chronology and one-out-per-start. Group operations serialize per company/site/work_date, lock selected sources in ID order and reuse request tokens only for identical selections. Already recorded checkout/early-leave timestamps are retained.

Local PGlite verification includes the existing GPS migration, actual RLS fixture and original coordinate/photo CHECKs. PASS: gate disabled, untouched old provenance, exact roster, other-site rejection, proxy month ownership, early-leave preservation, duplicate retry, request-token mismatch, foreign-worker anchor, forbidden direct insert/proxy spoof, immutable origin and blocked account.

Not verified: true concurrent separate PostgreSQL connections (PGlite fixture is sequential), full production migration chain/ACLs, UI integration, iPhone behavior, and compatibility with the staged vehicle exclusive-driver trigger. Both gates remain OFF. Candidate refresh may find new participants between preview/commit; only explicitly selected source IDs are processed. Ambiguous multiple starts are refused.

Existing `save_daily_report_destination_draft` allows company-member draft saving; signed edits need the requester's approved edit request. This migration does not rewrite it or link report completion. No notifications are emitted here: notification deduplication/recipient confirmation must be connected to successful report registration in later work. Bulk correction request authorization remains separate work; original GPS evidence must be preserved.
