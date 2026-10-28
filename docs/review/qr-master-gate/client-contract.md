# QR shared master flag — client contract candidate

The client recognizes `qr_attendance` only when the same response includes integer `qr_attendance_contract_version: 1` and a boolean flag. Missing, unknown or malformed contracts remain OFF. Reader registration derives from the exact same flag; a separate `qr_device_registration` value cannot enable it.

This is a proposed response contract, not an existing server capability. The current master getter, setter, proof whitelist and server enforcement must be extended and tested together before any activation. No new setter or editable toggle is exposed by this candidate. Existing fixed-OFF QR rollout gates remain unchanged. Permission checks, active-device proof, in-flight operation handling, audit records and real-device checks remain required. A true response is neither deployment evidence nor authorization by itself.

CI tests cover missing/unknown/string/double versions, malformed booleans, independent registration claims and the shared OFF/ON mapping. Local Flutter/Dart is not run.
