# Authenticated Navigator identity boundary

The previous home Auth gate loaded a future on explicit callbacks but did not destroy all pushed routes when the SDK emitted logout/account changes. The application now wraps the entire MaterialApp/Navigator in an identity boundary. It removes the subtree for one frame so shared global Navigator keys cannot retain old route state, then mounts a fresh Auth gate. Same-actor token refresh preserves current navigation. Stream failure destroys the subtree and fails closed; recovery starts a fresh subtree. The Auth gate ignores late reload callbacks after disposal.

Actual Navigator widget tests check private-page disposal, new Navigator identity, empty back stack, rapid account return, normal same-actor refresh and auth-stream errors. The dedicated workflow also checks the real app integration and existing secondary/actor tests. No server Auth/RLS changes or production writes.

This only handles SDK identity signals. Role changes and server-side revocation without a delivered SDK event are not proven by this client boundary. It does not erase screenshots, OS snapshots, global persistent document caches or already issued signed URLs. Those remain separate Auth/Storage verification tasks.
