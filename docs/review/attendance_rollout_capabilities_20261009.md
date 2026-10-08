# Attendance rollout discovery

Baseline main was verified through GitHub as
`a2a0ad26cebfbcc39ec99fe49f8b78d4ceb6c202`. The contracts reviewed were draft
PR #761 (vehicle claims), #764 (immutable driver meter), and #765 (group proxy
checkout). This migration does not require or apply those migrations.

RPC: `public.get_attendance_rollout_capabilities(p_company_id uuid)`.

```json
{
  "version": 1,
  "company_id": "requested-current-membership-company-id",
  "group_checkout_enabled": false,
  "vehicle_usage_enabled": false,
  "vehicle_meter_enabled": false
}
```

The caller must be authenticated, have current membership of the requested
company, and pass the existing account-access guard. Invalid/foreign/NULL company,
missing authentication and blocked accounts receive SQLSTATE 42501 without any
gate values. Clients must treat absent RPCs, exceptions, version/company mismatch,
missing fields, and any non-boolean-true value as OFF.

Only the private definer helper reads private gate tables, after those checks.
The public wrapper is security invoker. Neither function writes data. Private
tables remain inaccessible to authenticated/anonymous clients, and no enable API,
new gate rows, permission flags or role changes are added.

Absent gate tables/rows, default false, and unrecognized gate columns/types are
OFF. Group discovery also requires the exact group public/private RPC signatures
and request table, plus both exact public/private
`attach_group_report_sources(uuid,uuid,uuid[])` signatures. Checkout-only or
public-attach-only installations remain OFF so the UI cannot enable an incomplete
report flow. Vehicle discovery requires the claim table/claim function.
Meter discovery additionally requires both exact public/private
`record_vehicle_driver_meter(uuid,uuid,numeric,numeric)` signatures and the meter
snapshot table. A claims-only installation therefore never advertises meter entry.
Discovery is not permission to drive, proxy-checkout authorization, deployment
readiness, or authorization to activate a gate; existing scoped RPCs still enforce
those conditions. All staged features must remain OFF pending root's integration,
race, correction, delivery and device verification.

Verification runs the actual new RPC/ACL implementation in isolated PGlite, with
real authenticated/anonymous roles, company-membership SELECT RLS and private
table ACLs. Prerequisite functions are catalog-only stubs; this test does not
execute or validate staged driver/proxy/meter business operations. Synthetic ON
rows occur only in the test, never in the migration or production.

Command: `node tool/verify_attendance_rollout_capabilities.mjs <pglite-path>`.
No production migration or activation was performed.

Additional integration verification applies the actual staged claim/meter
migrations from #764 at `cded8afd06d8ce138c1910fee399ddbe6be2ec9f`
and proxy migration from #765 at `fa44c2badcecddb501c5637d7ca6656b13b84b36`,
using immutable separate CI checkouts. It verifies base-only/default/claims-only
OFF, synthetic ON discovery with actual functions, private-table and foreign
company denial, and executes an own clock-in/claim, actual proxy candidate and
commit RPCs, and the driver meter RPC. Capability reads create no business rows.
Gate OFF and blocked-account behavior are also checked after integration.

The real attachment migration is supplied as a third dependency checkout, pinned
to #771 at `8708d1d3101c7a3ec31ad397b9d38d6ba661ee0c`. The
integration test verifies actual checkout-only deployment stays OFF, then adds
attachment and executes successful saved-report attachment and exact retry.
All original GPS/claim/meter/proxy evidence fields remain unchanged.

Command: `node tool/verify_attendance_rollout_capabilities_staged.mjs <pglite-path> <vehicle-checkout> <group-checkout> <attachment-checkout>`.
This isolated synthetic fixture is not full schema, concurrent PostgreSQL-session,
production data, device, or rollout-readiness verification. Both business gates
remain unapproved and OFF outside test fixtures.
