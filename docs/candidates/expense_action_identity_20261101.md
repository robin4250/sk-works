# Stable action identity after removal or capability changes

Separate follow-up on frozen manager UI1720/2f3. No old backend/UI/personal/Auth-tracking/bridge head is rewritten. Not deployable or for the next iPhone Release.

Actual bridge1723 diagnostic4b34 job124688488833 failed before actor switching at `unknown removal result workspace`: deleting the default-style OutlinedButton let the following custom-style detail OutlinedButton inherit its animated State, causing incompatible TextStyle.inherit interpolation. Earlier54964 reached all RPCs but also failed its framework-exception assertion. These are product transition failures, not successful bridges.

The two actions now use stable keys from company ID, claim ID and a program action ID, not translated labels. The same claim's detail action keeps its State when the delete action disappears. Revision is deliberately excluded: the identity is the same action on the same claim, while callbacks and rendered metadata update to the latest revision. Parent actor/session retirement remains the responsibility of the existing page boundary.

Two focused regressions cover manager-deleted history and capability OFF, including correct detail callback identity, preserved original approval/withdrawal, zero deletion callback and no framework exceptions. They run only in the dedicated isolated fixture after source review. Backend SQL77dc, Auth/native implementation, financial reader, calculations, production data and notifications are unchanged.
