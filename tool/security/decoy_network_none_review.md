# Disposable decoy: kernel network boundary

This test-only candidate extends the existing loopback fixture without changing
its controller or transport. No SKO, Auth, database, production data or keys are
mounted. Only the three explicit JavaScript fixture files enter the container.
The container has no published ports, network `none`, no capabilities, a
read-only root, a non-root UID, no-new-privileges and CPU/memory/PID limits.

CI inspects that configuration before starting it. Inside, the test checks only
loopback interfaces, no IPv4 route and no non-loopback IPv6 route. Two fixed RFC
documentation addresses are used for immediate `ENETUNREACH` assertions; a timeout
does not count as a successful isolation result. There is no DNS lookup or real
remote target. Real loopback requests verify decoy rotation, quarantine/release,
operator rejection and a separate synthetic normal service remaining unchanged.
Existing request metadata remains bounded and contains no headers, payload or IDs.

The Node22 major image matches the existing fixture runtime. CI resolves its
local content-addressed image ID before create; this is not a claim of an immutable
registry digest or production supply-chain attestation. Pull/checkout happen on
the runner before isolation. The Docker daemon and runner are trusted boundaries;
the test does not prove the entire host has no network, protect against a kernel
escape, or provision durable monitoring/public hosting/WAF. The normal service is
synthetic, not a real SKO user or device regression test. No production deployment
or automatic account blocking is enabled. `deployment_ready` remains false.

Reference: https://docs.docker.com/engine/network/drivers/none/

Run only via the dedicated workflow or an equivalently inspected isolated Docker
container. The opt-in entry deliberately refuses a normal host invocation.
Syntax validation is not execution proof; record the exact CI head and result
before treating this boundary as tested. Production connection still requires
separate review, recovery and explicit approval.
