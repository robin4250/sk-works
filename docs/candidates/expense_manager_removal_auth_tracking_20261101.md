# Follow-up: unavailable Auth event tracking fails closed

This source is stacked separately on manager UI1720 at2f3. Existing backend1719, personal1721 and bridge1723 heads remain unchanged. Not deployable; no Phone shipment, main, SDK, Auth implementation, native, SQL or financial-reader changes.

The manager-removal default repository subscribes only if Supabase was already initialized at construction. Its dynamic actor/SID getters could become available after a later initialization while the original instance still has no Auth event subscription. This follow-up fixes tracking availability as false for that lifetime and denies later mutation/result adoption. Reopening must create a properly tracked repository. Explicit fixture streams are not proof of the production default initialization path.

Existing client fixtures now declare their empty synthetic event streams explicitly. One negative regression creates an instance without any event source, makes identity available later, and requires zero mutation/result RPC calls and zero new journal data. Actual SDK initialization ordering, process durability and device behavior remain unverified. Shared finance reader and legacy rollout remain RED.

Closed or errored tracking also permanently retires the instance, rather than permitting later new commands after a one-time epoch increment. Positive fixtures use explicitly live broadcast streams and dispose their repository instances. End/error negative cases cover both zero-call admission and in-flight adoption/journal retention.
