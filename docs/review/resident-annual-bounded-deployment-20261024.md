# Annual resident tax: bounded deployment preparation

This prepares the existing annual input backend for the payroll-list → tax-rate
settings entry. It does not create another annual input UI or another tax store.
The exact existing candidate is reused without changes:
`docs/candidates/resident_tax_annual_20261020.sql.review-only`, SHA256
`bf6e11a2bdfb91b6a5623d1f9ca116f1e9849196a4de0ad5debc500bda8b4da1`.

## Bounded change

- Adds only `resident_tax_annual_private`, its four empty audit/confirmation
  tables, eleven private functions and three public invoker RPCs.
- Keeps eight existing dependency functions, their definitions and attributes
  unchanged. The unit's three pinned financial/scope MD5 checks are retained.
- Protects the definitions and count/SHA256 of companies, memberships, workers,
  individual settings, payslips and the existing resident-tax state/entry/history
  tables. The observer outputs hashes and definitions, never financial rows.
- Copies the earlier PNG observer/strict checkpoint pattern, including a fixed
  empty search path so FK/function definition rendering is deterministic.
- Source installation does not input tax amounts, confirm an annual batch,
  recalculate payslips, change existing ACL/RLS, or change any original rows.
  Availability after installation is governed by the existing company/employee
  payroll permissions. There is no central OFF gate in this candidate.

## Installation and removal

Only a complete fresh protected before checkpoint can generate installation SQL.
The installation locks the eight originals in deterministic order, rejects a
stale checkpoint, verifies the exact fixed unit, then checks original data,
catalog, dependencies and namespace ACLs again in the same transaction.

After installation, an exact observation is needed to generate removal SQL.
Removal is permitted only while all four new tables remain empty, all originals
match, all fourteen function bodies/attributes and grants match, and the exact
installed checkpoint is still current. It uses no `CASCADE` and checks complete
before equality after removal. This is **unused code removal**, not a financial
undo. Once any annual confirmation/history is saved, this path refuses removal;
the existing audited row-level undo remains the legitimate financial operation.

## Verification

Five Python cases pass: source drift, incomplete/pinned drift, strict bounded
SQL generation, private exclusive artifact writes, and used-removal refusal.
Node syntax and diff checks pass. Local PostgreSQL execution was not performed.

The dedicated CI uses two separate fresh PostgreSQL 17 services:

1. Reuses the existing annual functional fixture without modification: annual
   confirmation/zero/idempotence/boundary/exception/draft-recalculation/manual
   and finalized-pay protection/CAS/permissions/late rollback/undo/concurrency.
2. New bounded-deployment fixture: strict stale-before refusal, late failure
   full rollback, install → unused removal exact original equality, empty
   initial schema, anonymous/viewer/other-company refusal, explicit owner
   same-value confirmation, durable retry, and used-removal refusal while
   original financial hashes remain unchanged.

These are synthetic application data and SQL-role fixtures, not actual owner
HTTP/JWT or iPhone proof. No production connection, deployment, tax input,
confirmation or undo is performed by this preparation. Root performs any real
observation, original review, deployment and receipt persistence separately.
