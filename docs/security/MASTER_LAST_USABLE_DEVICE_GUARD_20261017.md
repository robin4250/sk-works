# Master last usable device guard — review candidate

Base: bb78cc0ca39f72ad0b00898041fc536a3458f365. Production writes: none.

The existing device management screen allowed locking its last usable device
without confirmation. Both device management and recovery contact settings are
behind the trusted-device gate. An active locked device prevents first-device
bootstrap, and absent recovery contacts prevent dual-email recovery. This is a
product guard omission; it is not the user's fault.

The UI candidate confirms lock/revoke and explains that these disable Master
access rather than locking the screen. It refuses loss of the last locally known
usable device and warns about another trusted device and recovery preparation.
Current server responses do not expose this device's row ID, so the UI explicitly
says that self identification is unavailable instead of guessing by name/type.
UI checks are advisory and can be stale.

The review-only SQL outside migrations wraps existing legacy lock, optional proof
lock and revoke implementations. All take the enabled Master owner row FOR UPDATE
before a device row, then count other non-revoked unlocked devices in the same
transaction. Operations which remove the final usable device fail closed. A
locked-to-unlocked operation retains the original server authorization. Proofs
are still required/consumed by the original implementation; no Face boolean or
client assertion is accepted as server proof. Existing implementation bodies are
retained privately and denied direct authenticated/anonymous execution.

This candidate does not unlock the currently locked phone, add recovery emails,
change credentials, change roles or enable any rollout. Email registration alone
is not treated as sufficient justification to lose the final trusted device:
verified delivery and a tested recovery route are not implied by saved addresses.

The fixture runs only against disposable loopback PostgreSQL 17 and synthetic
identities. It covers last-device loss, valid unlock, operation proof preservation,
non-Master/anonymous/private-body denial and concurrent lock/lock, lock/revoke and
revoke/revoke using separate connections and observed row blocking. Identity,
provider, company and Master role snapshots remain unchanged. Existing locks and
revoked history are not silently reset by candidate installation.

Deployment is not authorized by source merge or fixture success. Preserve actual
schema, definitions/ACL, roles/company and selected device state securely; verify
isolated restoration, exact source prerequisites and effects; obtain specific
production approval. DDL installation must quiesce existing requests and exclude
concurrent migrations replacing wrapped RPCs. The original function names and
OIDs can be restored in isolation; never rollback by overwriting all current
production device state. The separate incident restoration procedure is reviewed
by the recovery lane and requires its own protected snapshot and exact approval.

Supported transaction isolation is READ COMMITTED. The guard rejects REPEATABLE
READ and SERIALIZABLE with a generic denial before reads/mutations, because the
other-device count must use a fresh snapshot after obtaining the owner row lock.
The isolated fixture verifies all three entry points fail closed at both rejected
isolation levels, while retaining the separate-connection READ COMMITTED races.
