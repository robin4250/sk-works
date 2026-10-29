# Selected employee initial bank registration — review candidate

This is a stacked successor to the frozen own-bank registration change. It adds
an employee-detail consumer and a **default-OFF, review-only** backend candidate.
No hosted SQL, grants, configuration, registration or activation was performed.

## Why a backend candidate is required

The existing bank table permits SELECT to the owner or an actor with the existing
`can_manage_payroll` permission. INSERT/UPDATE and its status-sync trigger require
the worker's own user. A client-side administrator flag, another employee ID sent
to the own API, or a SECURITY DEFINER wrapper alone does not provide an authorized
manager registration path.

The new path fixes the selected company and worker. It admits only a live,
non-anonymous, non-banned original Auth session with current company membership
and the existing payroll-management authority. Membership, delegated payroll
permission and active worker rows are locked. The save rechecks the same genuine
permission and never updates, deletes or upserts an existing bank record.

## Existing protections reused

- The existing primary-password broker validates the exact caller with GoTrue,
  verifies the password through a distinct temporary session and confirms its
  cleanup. It issues no proof when the new capability is absent, OFF, already
  registered or scoped to another employee.
- Operation `employee.bank.initial` binds company, worker and an input SHA-256.
  The existing private proof issuer, consumer and ledger remain unchanged. Their
  live SID, deletion barrier, banned/anonymous check, 120-second expiry and
  atomic single-use consumption apply. Only the original small scope/required
  dispatch and public service-only wrapper gain a bank branch.
- Manager INSERT reaches the unchanged table constraints through one private
  transaction context. It binds xid8, actor, original SID, company, worker,
  exact input digest and consumed proof hash. App/service roles cannot write it.
  The existing self branch is retained; only INSERT with that exact manager
  context is additionally admitted. No GUC or auth.uid/JWT replacement is used.
- Context is deleted in the same transaction. Errors roll back context, proof
  consumption and the insert. A per-worker advisory lock and the existing PK
  give concurrent initial registrations one winner.
- Capability and save return metadata only. Bank fields are not put in audit
  output, public receipts or proof targets. Client errors are generic, and an
  unconfirmed save is reloaded before another explicit attempt, never retried
  automatically. Existing bank contents are not read by this UI.
- The selected self route uses the existing own API only after the actual worker
  user matches the actor, with both selected IDs and the detail lifetime retained.
  Other employees cannot fall back to that route. App auth-owner admission,
  epoch/history and pending/failed logout quarantine fence all new client work.

The canonical digest is SHA-256 of UTF-8:

```
sko-employee-bank-initial-v1\n
<byte-length>:<company UUID lowercase>\n
<byte-length>:<worker UUID lowercase>\n
<byte-length>:<bank_name>\n
<byte-length>:<branch_name>\n
<byte-length>:<account_type>\n
<byte-length>:<account_number>\n
<byte-length>:<account_holder>
```

Names are trimmed and bounded to 100 Unicode code points; deposit type is one
of the existing three types, and account number is exactly seven ASCII digits.
The client converts fullwidth digits while retaining leading zeroes. Exact
normalized field strings are used in the digest and saved payload.

## Guarded artifacts and introduction stages

`tool/staged/employee_bank_initial_registration.sql.review-only` checks the
exact original definitions of eight prerequisite functions before creating
anything. It leaves existing private issuer/consumer/session/permission bodies,
table columns, RLS policies and their grants unchanged. New API grants inside
that file are a proposed introduction, **not authorization to apply it**.
The private gate returns false by default; authenticated clients cannot change it.

The separate stages still requiring operational review are:

1. Review the exact source/CI evidence, database catalog prerequisites, new
   context privileges and introduction/restore scripts.
2. Approve and apply the guarded SQL with the gate still OFF; verify original
   function attributes, existing data and genuine capability responses.
3. Approve and deploy the matching password-broker/client versions. A missing or
   OFF capability must keep manager registration unavailable.
4. Separately approve any server gate change and perform genuine session,
   selected-employee and existing-account checks before enabling the new path.
5. Public/TestFlight distribution and iPhone hardware confirmation are separate.

The unused restore is
`tool/staged/employee_bank_initial_registration.restore-unused.sql.review-only`.
It requires exact candidate definitions, an OFF gate, empty context and **no bank
proof history**. It restores original definitions/attributes and removes only new
API/helpers/context; existing bank rows and original documents remain. Once any
bank proof has been issued, that unused restore refuses; a used deployment needs
a separately reviewed non-destructive decommission plan, not deleted history.

The feature SQL never writes payroll statements, finalized snapshots, history
or signatures. Native and real-Auth fixtures assert those originals unchanged.
Existing readers may display live bank information under their current policy;
this candidate does not redefine those readers or backfill past payroll.

## Verification boundary

Fixtures contain synthetic users, employee rows and account values only. Hosted
inspection was restricted to function definitions, columns, constraints, RLS and
grants; no actual account rows or values were fetched. Native PG17 and independent
real GoTrue/PostgREST/password-broker tests exercise the review-only path with the
private gate enabled only inside their disposable fixture. Their success is
code/contract evidence, not production deployment, activation or delivery.
