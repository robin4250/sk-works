# All current company-registered allowance labels

This candidate follows the user's final scope: leave the company registration
screen intact; show its existing definitions in individual settings and checkout.
The reader covers legacy three slots plus all active additional company items.
It does not change the four quantity/payroll producer functions or registration
UI. The prior save-to-preview UI candidate is retained separately and is not an
integration dependency here.

## Read contract

New RPC: `public.read_company_registered_allowance_labels(p_company_id uuid)`.
Its invoker wrapper delegates to the new private definer
`company_common_allowance_private.registered_labels(uuid)`. The implementation
uses the existing source-pinned live-session/account guard, then explicitly
requires the current UID's membership of the requested company. Ordinary company
members can read names; owner/admin settings access is not borrowed. There is no
implicit company selection, `LIMIT 1` company fallback, schema grant, table grant,
new table, writer, adoption, activation or price exposure.

Response fields:

- `contract_version=1`, explicit `company_id`, `registration_scope='current'`.
- `source_versions.legacy_version` and `.common_version` are separate; legacy
  version may be null and an absent empty common catalog is version zero.
- Each item: `id`, `name`, `origin` (`company_legacy` / `company_common`),
  `payroll_type` (`all` for legacy, otherwise daily/hourly/monthly), `section`,
  canonical `unit`, original/display unit, nullable legacy slot/generation, and
  the corresponding `registration_version`.

The existing admin-state contract already classifies the legacy slots as
all-types/day/earning while preserving source display units separately. This is
not a new conversion from a label such as 回 to a guessed duration. New item units
are copied from their existing registered classification. Amounts, rates,
creator/updater identities and history are never selected into the public result.
Zero-priced registered items are still returned. Retired and other-company items
are excluded. All registered names are returned up to the existing 3+100x3 bound;
there is no silent truncation.

Unadopted legacy names remain visible, but missing IDs/generations/versions remain
null instead of being invented. The client exposes `selectable=false` until a
stable registration exists. Duplicate name text is preserved with its source
metadata. Callers must use stable source identity and the backend's exact choice
contract, not reconstruct identity from text or split a name into multiple tags.

## Consumer boundaries

`CompanyAllowanceLabelSource.read(companyId)` is unchanged. The new strict
adapter checks company, actor and captured token before/after its only RPC. It
has no writer, cache or subscription. It never falls back to the old max-three
endpoint and calls that a complete list. `snapshot.version` means common catalog
version; `snapshot.legacyVersion` is separate. Label metadata carries the stable
origin/ID/registration version needed by the separate sign/receipt owner.

The API does not claim worker-specific applicability, dated eligibility or an
amount already applied to payroll. Individual settings can display all unit and
section classifications while retaining existing personal names/amounts.
Checkout's owner excludes month-unit items and retains existing saved report
text; a month item must not be charged on every checkout. Hour/day quantity
resolution and price snapshot capture belong to the separate backend candidate,
which re-resolves registered source versions at normal report confirmation.
This reader alone does not satisfy checkout-to-payslip financial completion.

## Preconditions and evidence

Parent's read-only actual catalog was saved at
`private-company-registered-labels-20261024/catalog.private.json`: source guard
MD5 `68c68f275c23a22ba06d060c2923b9b9`, owner postgres, stable definer with empty
search path and owner-only ACL; five source tables owner postgres/RLS enabled;
authenticated already has private-schema usage; new signatures are absent.
The review SQL asserts those prerequisites, exactly matches all five observed
column/type/nullability/owner/RLS/ACL projections and refuses pre-existing
overloads. The Native fixture mirrors that observed column/security structure;
its surrounding keys/defaults and account/auth setup are declared synthetic,
not a copy of every production constraint or financial dataset.
Only its two new functions are created and authenticated EXECUTE grants are
added. PUBLIC, anonymous and service execution is revoked, including effective
privilege checks. Existing functions/tables are not altered.

Node syntax validation passed. Prepared isolated PostgreSQL17/actual local
PostgREST tests cover original-session-source drift refusal, ordinary member
read, all legacy/new pay-type/unit labels, zero-priced names, no monetary keys,
wrong company, anonymous/service/blocked/NULL-account/stale/anonymous-user
sessions, unchanged stored data and unadopted identities. JWT/session/account
surroundings are synthetic and explicitly do not claim real GoTrue/provider
proof. Flutter adapter tests cover the same data shape and stale actor/token
refusal. Native and Flutter tests await remote execution; no production apply or
main merge has occurred.

Supabase primary database-function/API permission documentation was checked via
`search_docs`: https://supabase.com/docs/guides/api/securing-your-api . The
changelog markdown fetch was attempted and rejected by the fetcher's unsupported
`text/markdown` handler; no new client API was inferred from that failure.
