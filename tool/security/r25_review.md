# R25 pre-insert private boundary (review only)

Four new files; exact original source catalog reused from R24. No production
writes, business-row retrieval, credential retrieval, data move or original
constraint changes. This candidate is isolated source, not a deployment hook.

## Boundary and trust

The exact two existing private creation RPCs are patched, preserving the original
access/quote/draft/preview/fingerprint/receipt checks and numeric expressions.
An additional existing enabled-Master/account check applies only to these LINE
creation RPCs; ordinary company invoice generation/settings are unchanged.
Immediately before each invoice INSERT, after existing validation, a fresh UUID
and validated company/current actor are recorded in private.r25_registry. The
invoice INSERT explicitly uses that UUID. Existing durable lineage INSERTs run
unchanged, then the temporary registry row is removed in the same transaction.
Historical cleanup follows its command receipt and durable-link batch INSERT.

R19 invoice classification, R20 notification classification and the actual lazy
approval helper recognize both registry and durable links. Consequently, the
existing synchronous invoice trigger sees the boundary before any ordinary
company approver or notice can be created. This deliberately creates **zero**
automatic company approval rows even for a Master. No private self-approval or
private approver configuration is invented; that product workflow remains absent.

The registry has RLS and no client CRUD grants (PUBLIC/anon/authenticated/service
roles denied). It has no public setter/API. Only exact hash-guarded Master-only
creation bodies create records, with server-generated UUID, non-null actor and
company after existing validation. A title, snapshot marker, user_metadata, GUC
or caller-selected staging flag never authorizes classification. The fixture uses
a claim change only as a controlled observer test; product code never does so.
Original function OID/owner/ACL/config are preserved. Any body, owner, configuration
or exact insertion-anchor drift aborts the whole transaction.

## Alternative and constraints

The original regular invoice lineage has a non-deferrable invoice FK; historical
links have a non-deferrable command-receipt FK. Reordering durable data ahead of
invoice INSERT would therefore require changing constraints/receipt sequencing.
A separate temporary private registry leaves those original relationships intact.
UUID collision is still rejected by the existing invoice primary key, rolling
back the registry with the failed statement. No database role is reset or renamed.

## Verification and limits

The fixture executes both complete original creation bodies and the actual invoice
trigger/helper. Access, draft/quote retrieval and preview generation use explicit
synthetic helpers; real GoTrue, source parsing, preview authorization and other
production invoice/payroll triggers are NOT reproduced. The old creation ordering
first reproduces a company approval and notice leak. After patching, a trigger
observer confirms staging is present, a non-Master classifier denies, and notice
classification recognizes protection before the public invoice write completes.
Both regular and historical creation keep totals, write durable lineage, clear
staging and preserve command idempotence. Existing snapshots are restored.

Direct client staging CRUD and privilege checks deny. An injected AFTER INSERT
failure rolls everything back; a subsequent fresh command succeeds. A disposable
forced UUID collision also refuses without changing existing invoice data.
Latest PG17/PostgREST CI must independently verify real HTTP wrappers call these
same private bodies, non-Master creation refuses, Master creation/receipt replay
succeed, no company approvals/notices appear and ordinary REST cannot read the
new linked invoice. These wrappers/observers are fixtures only, not product APIs.

Existing previously copied approvals/notifications/final attendance are not
removed. Unknown provenance, direct writers, membership/invites, external push
history, signed URLs, real access/session revocation and full UI verification
remain separate blockers. This candidate closes only this tested creation path;
it is not TestFlight safety approval. Master-private approval completion remains
unimplemented by design pending the intended workflow.

Before production: authorized protected backup, relevant complete restore proof,
current exact definitions/ACL/dependencies and trigger comparison, normal and
Master UI comparisons, impact report and explicit approval. Rollback is tested
only in a disposable environment; never overwrite later real data with an old dump.
