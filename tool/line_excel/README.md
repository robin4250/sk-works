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

`--login` accepts an existing account's phone/email and hidden password through
a real local terminal. `auth.py` keeps access/refresh tokens only in memory,
validates the user with Auth, rotates expired tokens without changing actors,
and requests `scope=local` logout for this new session only. It never creates
accounts, sends SMS, changes passwords or revokes sessions on other devices.
The Excel launcher loads a public key from local `接続設定.json` when necessary
and selects this interactive login if no externally supplied JWT is present.
Phone normalization matches `JapanPhoneRules`; OAuth-only and MFA flows remain
unsupported. Real password login must still be verified by the user locally.

Run offline checks: `python3 -m unittest discover -s test/line_excel -v`.

Still unverified/unimplemented: real user authenticated message retrieval,
real refresh-token/login operation, dictionary editing UI, automatic Excel refresh,
verified monthly totals, final invoice layout and rounding parity, protected
deletion/restore/permission management and all native Mac/Windows/iOS/iPadOS
operations. Local SQLite is an original archive, not an authorization boundary.
Do not expose it or a financial workbook to general users.
