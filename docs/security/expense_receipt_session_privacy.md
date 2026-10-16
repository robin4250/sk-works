# Receipt preview session and signed URL boundary

Baseline audit: 04d90559c8929c71b0b91f743066795b28007067. No production database, Storage object or access policy changes.

The existing expense receipt preview now drops its image and its own decoded-image cache entry on logout, actor switch, auth-stream failure/completion, or background/inactive transition. Revocation is sticky across returning to the original actor. Pending old responses cannot repopulate the preview. Resume and same-actor auth refresh obtain a new signed URL through the existing Storage authorization path; permission failures never retain the old image. The local lease starts before URL acquisition and expires after the existing 300-second lifetime.

This change does not revoke previously issued bearer URLs on the server, erase screenshots/OS snapshots, remove all caches throughout SKO, or guarantee immediate detection of role changes while no authorization/auth/lifecycle event occurs. Storage URL expiration and server-side session revocation require actual isolated Storage/Auth transport tests. It does not claim a UI mock proves production RLS or GoTrue behavior.

The tests execute the real widget with injected asynchronous authorization results and auth events, including late responses, permission revocation, expiry, background/resume and normal first display. The dedicated Flutter workflow must pass before integration. Device behavior and live Storage HTTP are separate verification items.
