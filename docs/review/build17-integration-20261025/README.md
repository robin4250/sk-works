# Build 17 integration candidate — 2026-10-25

Base main: 7e6eda88513f1becc673b25e9871abf279ff3303. Build 16 candidate is tf-candidate-tt0_5xt8; its upload/install completion has not been confirmed. This branch must not replace or relabel that IPA.

Combines existing original Git blobs from PR1404 (login/security/phone preparing), PR1408 including PR1407 (secondary attendance entrances and friends return), and PR1409 (explicit worker confirmation when saved work category is null). All 32 paths are disjoint. Security paths are also disjoint from all changes between its baseline04516917 and currentmain. Commit parents retain all three original heads; no duplicate cherry-picks.

The worker confirmation recovery keeps saved report values as unconfirmed inputs and requires explicit category selection. Existing permissions/source checks/revisions/server validation remain. Real signatures and attendance must be entered by their owners; do not insert a category, confirmation, signature, or payroll row through deployment SQL.

No production DB/Auth/provider/config/role changes. Registration rollout remains paused; do not automatically reactivate after CI. Collector admission remains OFF and production security blockers in the saved closure document remain unresolved.

Candidate source is not an IPA. Run focused CI on the combined tree; use exact final-main Flutter/iOS/provenance/secret results before a new Release build17. Never rerun successful unaffected Native/GoTrue suites merely for this integration. Mac build/upload/install steps are user-run, one command per operation. Existing build16 remains intact.
