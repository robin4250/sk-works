# Outgoing source and prepare observation — review only

This is two bounded **read-only** contracts for the unfinished outgoing flow.
It does not create drafts, record consent, render/register PDFs, send orders,
activate the feature or provide a working composer UI.

`outgoing_context(site, trade)` derives the current sole company/management role
through the canonical C guard, requires the exact linked/accepted subcontractor,
and reads registered issuer, selected-site and trade-directory fields. The
representative is read through the existing exact profile helper. Own registered
seal context is reused. Field whitelists exclude bank, email, prices, notes,
original URLs and authorization-changing inputs. Self FAX comes from the actual
company column. The trade directory has no FAX column: no guessed peer FAX is
introduced. Context and input are intended for scoped RAM only.

`observe_prepare(site, document, local, trade)` follows existing prepare's lock
order: current company/peer pair, site-document scope advisory lock, canonical
document advisory lock, then site/saved rows. `not_observed` means **UNKNOWN**,
not cancellation. An original delayed HTTP may still arrive later. Every result
has `journal_clearable=false`, `may_prepare_again=false`, `can_send=false` and
`retry_automatically=false`. No result clears the ID-only journal.

Only an exact first revision, open/epoch-zero, same creating actor/company/site/
trade/local binding, intact stored body hash and currently registered party
objects can return `prepared_review_required`. Any existing consent, consent
event/receipt, later revision or render job blocks this path and returns no body.
The returned body is the server's observed draft and must be visibly reviewed
again. It is not proof that a formerly lost client RAM body was identical; the
client's old body digest is deliberately not persisted. Old SID/job/consent/PDF
records are never rewritten or revived.

The source SQL has no tables, grants or persistence changes. The existing profile
value helper body matches the public candidate and captured MD5
`06ce79748602c8ca5aebda226bc7f742`. Its extension table is one explicit additional
dependency; the prior A eight-body/fifteen-relation proof does not cover it. The
old protected test harness has a two-column synthetic extension table; the fixture
extends its disposable nonfinancial columns and uses the exact existing helper
declaration. It reproduces canonical C's required authenticated guard EXECUTE
after old owner-only guards have run. This is not a fresh production installer or
proof of complete current C deployment.

The Dart methods validate current actor/company/SID, exact response fields and
negative send/retry/journal permissions. They do not persist source/body/seal or
resolve approval/recovery journals. The Edge commands accept UUIDs only and keep
the existing 4096-byte request cap; no client-supplied SQL, company or body is
accepted.

Remaining: atomic prepare/bind frontend command, draft identity journal staging,
permanent retirement for definitive cancellation, RAM input/recipient/back flow,
explicit review/consent, canonical job/PDF/send connection, full current baseline
composition, independent review, authorized production deployment and iPhone
confirmation. No completed fixture or CI result closes those gates.

Local evidence: PGlite 59 outgoing checks, including six dependency/ACL/default
drift rejection-and-rollback cases; existing site history 45, package 295 and
bound-consent 238 checks pass. HTTP 16 tests pass. Dart syntax parsing succeeds.
Native lock-wait and Flutter client results require current-head completed CI.
