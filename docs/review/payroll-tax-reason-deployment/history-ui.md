# Read-only adjustment history entry

The existing individual-payroll settings page adds a compact entry beside its
insurance settings. It opens the selected worker/company, preserving unsaved
parent inputs. The new page calls only `payroll_workspace` and the existing
`read_worker_payroll_tax_adjustment_history` RPC; it has no save, delete,
recalculation, export, alternate audit store or old-writer fallback.

It deliberately does not query the new capability RPC: a separately approved
incident pause revokes that capability and reason-save entries while retaining
authorized history reads. An absent history RPC is shown as unavailable, never
as an empty history. Other failures show a generic retry state without raw SQL
or cached employee records. A successful empty response is the only path to the
empty-history message.

Scope and permission are checked through the canonical payroll workspace before
and after the read, in addition to the history RPC's server authorization. Exact
company/worker/version/envelope and bounded record identities are validated.
The existing captured-token, SDK/gateway-history and lifecycle guard is reused;
no authorization helper is broadened. Parent load-generation/selected-scope
changes retire the old target. Backgrounding or authentication invalidation hides
records and late responses cannot revive the route. Periodic 15-second access
checks preserve the reader's expansion state; they do not promise instantaneous
remote permission revocation. Server authorization remains mandatory on every
read. The page stores nothing persistently.

Reasons, effective month and change time are visible immediately. Before/after
amounts and audit identity are expandable. A missing override is shown as no individual correction, not an invented zero
or a fabricated historical automatically calculated amount. An explicit zero
remains zero. Calculation-method changes are displayed separately. Unknown actor names are not invented:
the returned actor ID and saved version are available under record details.
The returned newest-100/truncated contract is preserved. The display does not
recalculate taxes or rewrite historical condition values.

This UI alone does not install or enable the reason backend. Production HOLD
remains and real-device behavior still needs owner verification after a signed
Release update.
