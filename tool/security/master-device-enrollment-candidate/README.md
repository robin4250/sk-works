# Master device enrollment — safety design candidate

Status: design only, not deployed or enabled. Existing passwords, devices and
access policies must be preserved. Device enrollment must be performed by the
owner after the entire flow and recovery have been tested.

## Existing components to reuse

`tool/staged/master_device_lock_reauthentication.sql` provides a default-OFF
operation proof for device lock, and
`tool/staged/master_last_usable_device_guard.sql.review-only` provides a
candidate last-usable-device guard. Neither establishes that bootstrap, revoke,
or registering an additional device is safe. Check the exact current function
definitions and deployed gates before using either candidate.

The existing bootstrap RPC accepts a master session when there are no active
devices, without server-side second-password proof. A local biometric success
cannot itself be verified by the server: do not treat a client boolean as
evidence. Existing lock/revoke entry points also need server-side enforcement,
including concurrency-safe protection against losing the last usable device.

## Proposed protocol, not implementation

* Keep enforcement OFF until compatible clients and recovery are demonstrated.
  The old RPC must be gated at the database boundary after activation so a
  direct API call cannot bypass the new path.
* Verify a live, non-anonymous master session and deletion/banned barriers.
  Verify the second password using the existing credential checker; ensure
  failure counters commit even when a password is wrong. Never log passwords,
  tokens, recovery codes or private keys.
* Use a short-lived, single-use server-issued challenge bound to the actor,
  live session, action, exact canonical device public key and operation nonce.
  A trusted device must cryptographically approve an additional enrollment;
  a hardware-backed non-exportable private key should require user presence
  where the platform supports it. Client-reported Face ID is not proof.
* First-device bootstrap has no trusted device to approve it. It requires a
  separately verified, owner-controlled recovery channel and a secure enrollment
  procedure; second password alone must not be presented as biometric proof.
  If those prerequisites are not available, fail closed and preserve recovery.
* Registration and approval consume the challenge atomically, under a
  per-master transaction lock, recording only necessary audit metadata. A
  maximum of three active master devices is a proposed rule subject to legacy
  inventory and recovery compatibility; do not automatically remove any devices.
* Lock or revoke requires an action-specific proof and locks the owner's device
  set before checking the last-usable-device invariant. Recovery is a separate
  audited process, rather than an unchecked bypass. Concurrent requests must
  not revoke all devices.
* iPhone, iPad and Mac identity and key support must be explicitly tested;
  browser access is unsupported until an appropriate secure WebAuthn design,
  origin verification and recovery are demonstrated. Do not infer device type
  solely from a shared iOS platform flag.

## Required verification before activation

Real PostgreSQL tests must cover direct calls to old RPCs, wrong password and
lockout, expired/replayed/foreign-session challenges, actor and device-key
substitution, two concurrent first enrollments and concurrent last-device
revocation, approval by a revoked device, recovery and restart, audit retention,
and an unchanged legacy user/session. Test legitimate iPhone, iPad, Mac and
lost-device recovery on the actual platforms. Verify accessibility, owner
identity, explicit approval, key restoration and clear rollback. Do not activate
or claim 3-device registration is available before these checks pass.
