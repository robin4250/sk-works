# Qualification parser process boundary candidate

This review-only prototype starts a host-selected absolute executable and worker with an empty environment, passes only the selected file bytes and declared MIME over stdin/argv, bounds stdout and wall-clock time, and accepts only a successful exit with the exact response. On completion or failure it attempts to kill the worker process group on POSIX. It is not enabled or wired to the inspector.

This is not an OS sandbox. It does not itself restrict filesystem, network, native memory, CPU, processes that escape their process group, or worker identity/integrity. A malicious or defective worker must not be trusted based on this prototype. Production requires a pinned and verified worker image, external isolation and resource limits, restricted filesystem and network, whole-tree cleanup, a trusted session/slot adapter, an end-to-end deadline including DB commit, and real Storage deployment/version verification. Abort/timeout must be demonstrated to prevent later receipts. No production permissions or deployment are added by this candidate.

Tests use generated synthetic workers only; no user files, credentials, or production state are involved.
