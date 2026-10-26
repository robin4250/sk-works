# Explicit checkout/report choice (OFF candidate)

Base: main `112b989978b2f784e66854d12315fec649ecbadf`.

The existing registration reader blocked every worker immediately after checkout. This optional layer uses the server's same-day, same-destination clock-in roster. One member continues directly; multiple members explicitly choose report creation or checkout only. Checkout-only remains a persisted unfinished report source and can later be resumed through the attendance-sheet create/resume action. First checkout does not assign reporting responsibility. Starting a report is durable; the existing persisted work-description/reporter-signature checks release it.

All choices bind the authenticated live actor to their own source, company and worker. The expected server scope includes the current roster. Concurrent choices serialize on the source; a started report cannot revert to checkout-only. Retries preserve the first timestamps; later explicit creation retains the earlier checkout-only timestamp. No real report, signature, attendance entry or financial row is created by choosing.

Install is transactional and default OFF with exact original reader MD5 guard. The original function OID and ACL remain intact. Unused restoration preserves the original definition/ACL and refuses activation or saved choices. No production apply or activation is performed here. Enable only after the matching client is installed and the global registration rollout is intentionally activated. An older client cannot parse the new states.

Validation: dedicated PG17 job uses the actual established registration bootstrap/reader, plus single/multiple/deferred/persisted/retry/source-actor/reporter-release and unused restore cases. Flutter checks run only in CI.


## Explicit general-menu and historical start

The monthly list remains read-only. Its `+` action reads a separate actor/source-bound creation list and requires the user to choose the real saved checkout. An enforced flow without a matching source does not open the old free editor. Another worker's administrative path and an OFF capability remain separate. Cancelling the picker writes nothing.

The creation reader can list saved sources before the rollout start date. Reading them does not add any gate obligation. Only an explicit `choose(create)` stores a start and includes that one historical source in subsequent gate reads; unselected historical backlog stays outside the gate. The rollout start date itself is not widened. Source choice and normal report creation remain separate: choosing never fabricates a report, attendance, signature, payroll or invoice.
