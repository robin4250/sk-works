# R24 known-lineage lazy approval synchronization (review only)

Five new files. Source-only candidate, zero production writes and business-row
reads. Catalog definitions, ACL/config and trigger/FK metadata only were read.
The actual helper previously stubbed by R20 fixtures is now exercised.

`private.ensure_invoice_approval_rows(uuid)` has body MD5
b96d072260cb54857a28bb867b508f57, postgres owner, SECURITY DEFINER, empty
search_path and NULL/default ACL. This candidate preserves all those fields,
including existing ACL (not silently broadening or revoking it). Private-schema
exposure/USAGE and broader callable paths require separate review.

The candidate inserts one early RETURN when either durable known LINE lineage
contains the invoice ID. No actor, including Master, automatically copies ordinary
company approvers into a linked invoice. Ordinary invoice lazy synchronization is
unchanged. Existing linked approval rows are not deleted or repaired; legitimate
Master approval without a private approver setup may remain unavailable. A separate
private approval workflow has not been specified and is not invented here.

Local fixtures install the exact real helper and execute both lineage sources,
ordinary/Master callers, existing ordinary lazy synchronization, original metadata
restoration and changed-body refusal. PG17/PostgREST adds a fixture-only public
probe that calls the real private helper; it is not a production endpoint or
GoTrue validation. Original calculation source is unchanged.

## Confirmed creation-order blocker

The actual AFTER INSERT OR UPDATE invoice trigger calls this helper, then queues
approval notifications. Both real creation function definitions are saved as
source evidence: create_line_invoices INSERTs the public invoice before inserting
line_invoice_submissions; create_line_historical_invoices INSERTs all invoices
before adding command receipt and historical links. In the disposable fixture,
the exact trigger creates a non-Master company approval and notification before
lineage insertion. That failure is deliberately asserted, not claimed fixed.
The reduced ordering fixture does not execute the complete creation RPC and its
preview/receipt dependencies. Ordinary RLS after commit does not prove an external
push was never queued during creation.

No client-editable snapshot marker, title, GUC or user_metadata is used as trusted
classification. A separate pre-insert private registry proposal must close this
window without weakening existing non-deferrable invoice/command constraints.
Until verified, creation remains a TestFlight blocker. Direct writes, unknown
provenance, existing attendance/payroll copies, signed URLs and external push
remain outside this candidate.

Before production: protected backup and successful relevant restore, exact
metadata/ACL/dependencies, normal administrator and Master UI comparisons, impact
report and explicit approval. No migration/deployment hook is included.
