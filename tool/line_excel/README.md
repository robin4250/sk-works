# LINE Excel preparation

Isolated read-only tools for the Excel integration requested on 2026-10-19.
They do not replace the Flutter import implementation or modify production data,
RLS, authentication, finalized invoices or original messages.

`core.py` provides dictionary tokenization, conservative worker status assignment,
occurrence ranking, immutable SQLite message revisions, cross-source overlap
review and Decimal draft arithmetic. Parsed entries remain unapproved.
Image schedules do not become attendance facts. The previous October total must
not be imported as confirmed attendance.

`sync.py` uses the existing `line_shared_chat_groups` RPC and a user JWT to read
`origin=line` messages through existing RLS. It supports explicit group selection,
an inclusive JST date window and pagination until empty, including deployments
whose server row limit is smaller than the requested page. Authentication is
revalidated before local saving. Credentials must be supplied through local
environment variables `SKO_ANON_KEY` and `SKO_ACCESS_TOKEN`; never send tokens in
chat, commit them or put them in spreadsheets. Service role keys are rejected.
No credentials or database rows are included in this repository.

Run offline checks: `python3 -m unittest discover -s test/line_excel -v`.

Still unverified/unimplemented: real user authenticated message retrieval,
refresh-token/login integration, dictionary editing UI, automatic Excel refresh,
verified monthly totals, final invoice layout and rounding parity, protected
deletion/restore/permission management and all native Mac/Windows/iOS/iPadOS
operations. Local SQLite is an original archive, not an authorization boundary.
Do not expose it or a financial workbook to general users.
