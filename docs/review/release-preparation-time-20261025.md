# Release preparation time — 2026-10-25

Current upload preparation includes CI waiting, Mac Release/archive creation, Transporter transfer, and Apple processing. These are separate stages; no transfer or Apple-processing speed claim is made.

The iOS CI job repeated full flutter analyze and flutter test already performed by mandatory Flutter CI (tool/pre_device_release_gate.sh), then built Debug and Release. This candidate removes only the duplicate full analysis/tests from the Mac runner and its Debug build. It keeps the full Flutter CI workflow unchanged, including all tests and Android build; iOS project-generation checks, dependency pins, permission/ATS/Face ID/location descriptions, OAuth callback checks, Bundle ID and Release compilation remain.

Release creation still requires the exact final main's successful Flutter CI, iOS CI, Secret Scan and TestFlight provenance. PR and final-main Release builds remain; no successful result is claimed for a different source tree. The Mac candidate preflight and signed IPA verification remain unchanged. Existing artifacts/build numbers are never relabelled, overwritten or uploaded by this change.

The earlier combined Flutter test phase was about ten minutes in run40180326494. This is evidence of duplicate work, not a promised wall-clock reduction: runner queues, CocoaPods, caching, signed Mac archive/export, Transporter throughput and Apple processing can still dominate. Measure the new iOS job after completion before quoting a reduction. Source app behavior/DB/Auth/payroll/signatures unchanged. Refs #273.
