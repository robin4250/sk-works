# Owner-only TestFlight handoff preparation

This support branch preserves a command generator and its historical template. It does not create an IPA, upload, install, modify production, or authorize distribution.

Before generating a real handoff, independently verify the final merged main SHA, the required successful main CI runs, the complete deployment prerequisites, and an unused build number against both the owner's private checkpoints and App Store Connect. Do not substitute the template's historical SHA or build number. The generated command verifies the exact main SHA and four named CI runs, stops if they are not already successful, refuses an existing same-or-higher private build checkpoint, creates an isolated candidate, checks commit/build/bundle ID/IPA hash/distribution, and asks macOS to open the resulting IPA with Transporter. It does not upload the IPA.

The `open -a Transporter` handoff has not been tested on the owner's Mac for the candidate. A successful process exit is not evidence of IPA acceptance or upload. Preserve previous IPAs and inspect any incomplete candidate before retrying. Owner internal testing is separate from employee distribution.

A dummy SHA and build 24 were used only to generate and parse a command, checking static safety markers. No generated command was executed. This is not an approval or a final release SHA.

The isolated candidate helper verifies every prior build number while holding the existing candidate lock, rejecting the same or a higher number even for a different commit; malformed or incomplete checkpoint inventories are rejected. A manual prompt requires the owner to verify App Store Connect and type the exact confirmation before starting. This is not an automated query or proof of Apple-side availability. The generated command explicitly disables Python optimization so assertion checks remain active. Synthetic inventory tests pass; actual Mac, Transporter and App Store Connect integration have not been tested. The branch remains review-only.
