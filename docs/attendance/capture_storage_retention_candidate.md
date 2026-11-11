# Attendance evidence Storage DELETE boundary (isolated candidate)

The harness executes the existing DELETE policy from
`20260920211200_allow_orphan_attendance_evidence_cleanup.sql` unchanged in an
in-memory database. It also reuses the existing SELECT policy expression from
`20260920210500_restrict_attendance_evidence_privacy.sql`. Worker and manager
identity helpers are synthetic prerequisites; production auth/feature roles/RLS
are not changed.

The baseline demonstrates that the owner can delete a photo referenced only by
an archive, and a manager can also delete a photo with a live public reference.
The candidate appends both live-reference and archive-reference exclusions
outside the entire actor OR expression. Both identities retain live/archive
photos, while genuine orphan cleanup still works. Other buckets, other companies
and malformed paths are rejected. The authenticated role cannot SELECT the
archive directly. A synthetic archive lookup failure propagates and aborts
DELETE for both identities rather than being treated as an empty archive.

All 28 baseline/candidate actor/scenario combinations execute SQL DELETE as a
non-owner `authenticated` role, with RLS enabled on synthetic `storage.objects`.
The dedicated boundary workflow runs this harness using PGlite 0.3.14:

```sh
node tool/verify_capture_storage_retention.mjs /absolute/path/to/node_modules/@electric-sql/pglite/dist/index.js
```

This proves retention of SQL Storage object rows only. It does not prove photo
bytes exist or that Storage API/service-role/lifecycle deletion, signed URLs,
concurrent reference creation or actual production archive authorization obey
the candidate. The archive helper is a fixture-only SECURITY DEFINER with a fixed
empty search path and explicit execute grant; it is not a proposed production
authorization implementation. INSERT, UPDATE, production policies, retention
periods and rollout gates are untouched. A production design must resolve those
boundaries before applying any policy change.
