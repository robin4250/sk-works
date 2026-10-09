# GPS original evidence: additional isolated boundaries

This follow-up reuses PR829's completed management-retention fixture rather than
repeating it. The harness pins its reviewed Git objects (`46f7099482f5fa203613873b8dbd2469a3f612a0` and
`0ba3d120199e5fd43caad9967e20f958fe7d17e0`); those commits must be present in the checkout (a shallow clone must
fetch PR829 history first). Runtime: `@electric-sql/pglite@0.3.14`.

Run from the repository root:

```sh
node tool/verify_capture_retention_boundaries.mjs /absolute/path/to/node_modules/@electric-sql/pglite/dist/index.js
```

The new assertions first reproduce the existing gap: a fixed capture UUID can be
inserted again after management deleted its live row, despite the experimental
archive retaining it. An isolated INSERT trigger then rejects that archived UUID
with SQLSTATE 23505 for both identical and altered retry payloads. This tests direct INSERT, not the complete production capture
RPC, concurrent retries, or user-visible retry handling.

A synthetic route child reproduces the production
`route_journey_captures.source_clock_in_id ON DELETE CASCADE` direction. A parent
BEFORE DELETE snapshot saves the intermediate photo path/payload before cascade.
The original child's `daily_report_id` is also preserved. Its `created_by` remains the capturer; `changed_by` is the actual
management `auth.uid()` actor, separately recorded. This tests database row
retention, not retention/existence of the Storage photo object.

No production migrations, auth/RLS, rollout setting, expiry period or live
Supabase data are changed. The synthetic fixture's pre-existing capture gate is
local only. Turning on production capture is outside this proof. Full PostgreSQL
concurrency, production RPC UUID rejection, worker/company/account deletion,
archive access authorization, report child/signature completeness, Storage
lifecycle and retention policy must be resolved before a production design.

The dedicated workflow fetches and verifies both pinned Git commit objects before
running these assertions; no unreviewed PR head is used as fixture input.
