# Payroll reason installation and incident pause — review only

Production HOLD remains. This package is an offline generator and disposable
fixture; it contains no production catalog capture, employee record or installer.
The existing candidate remains SHA256
`4277c2581a8fabb9e4dc0a9ee9ad07379d17afdd210006d49e74fa0b464e7fc6`.
The existing saver, validator, authorization functions, calculator and original
condition history are not edited.

`build_payroll_tax_reason_review.py` reads explicit private captures and that
pinned source, normalizes omitted/full prosrc export shapes using the exact
function definition and digest, and emits one private review transaction. It
checks every captured pg_proc attribute and definition before and after, plus
the complete captured relation/column/constraint/index/trigger/policy/default-ACL
scope. An existing additive object or drift refuses installation. The six new
functions must have their exact body, signature, owner, security mode and narrow
EXECUTE ACL; unknown inherited roles are rejected. The sidecar must remain
owner-only, RLS-enabled and protected by its append-only trigger.

Installation writes no payroll business row. However **the capability returning
version 1 immediately enables permitted manual-adjustment operations in existing
clients**. There is no separate master OFF switch for this contract. Approval
must explicitly include that effect. A later user save delegates to the unchanged
saver and may recalculate eligible automatic draft payroll from the effective
month onward. It does not authorize altering finalized payroll or filling in
invented premiums. Old clients and the general legacy settings API remain
compatible; this is not a universal reason mandate for every old writer.

The history-read RPC is provided by the existing candidate, but there is currently
no client history display calling it. A separate small UI candidate can expose
read-only scoped history under the existing edit/view policy: use the returned
company/worker/version receipt, newest 100 rows and truncated state, show effective
month, reason, actor and before/after values, and retire the page on SID/company
change. Reuse this API; do not add another audit store, rewrite history or pretend
installing this backend completes that UI.

The new verifier reuses the original SQL boundary/concurrency verifier without
weakening its assertions, replacing only its installation input with the guarded
transaction. It reproduces observed public function default EXECUTE grants,
rejects an unknown inherited role, refuses a changed direct authorization helper,
forces a postflight error to check complete rollback, and then runs all original
reason/receipt/CAS/SID/finalized-value tests. The authorization/basis-reference/
payroll-refresh prerequisites remain explicit synthetic fixtures; this is not a
live GoTrue or real payroll calculation correctness claim.

No destructive rollback is supplied. Before any separately approved deployment,
preserve fresh full catalog/default ACL originals and serialize source changes.
After COMMIT, reconcile the exact committed identity; a lost acknowledgement is
not permission to blindly retry. Preserve every append-only reason and condition
history record.

`build_payroll_tax_reason_pause.py` prepares a **separate permission-change**
review from an exact committed private function/table receipt. After independently
stopping new reason writers and waiting for in-flight work, it can revoke only
the new capability and public/private reason-save EXECUTE grants, leaving scoped
history reading and all legacy APIs available. It refuses later function/table
drift, preserves source bodies/OIDs and deletes nothing. Its stopped-writer
setting tests a condition; setting a string does not prove operational quiescence.
The disposable fixture rehearses refusal without that condition, postflight
rollback, later dependency drift, actual pause, retained history reads and all
business rows unchanged. Production application or pausing still requires a
specific reviewed approval; neither is performed by these tools.
