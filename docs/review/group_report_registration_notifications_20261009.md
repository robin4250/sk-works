# Group report registration notification connection

The explicit 日報「登録」action publishes only after save_daily_report_destination_draft, attendance linking, exact group source attachment validation and report reload succeed. Internal draft saves before reporter/responsible signatures do not publish. Site-based rosters must contain actual clock-in IDs and clock-out timestamps for every row; empty, manual, unfinished or route-based rosters are not published.

The existing publish_saved_group_report_notifications RPC owns author/account membership, saved roster evidence, recipients, company rollout gating and durable receipts. The client sends only the saved report ID. Zero covers rollout OFF or prior receipts and is not presented as notifications sent. Missing staged RPC is treated as unavailable. No production migration or rollout activation is performed.

A publication/network/result error is separate from report registration failure. The UI keeps the exact saved report ID and offers notification-only retry. Retry calls no report save, INSERT, evidence linking or approval RPC. Selecting another date/site or changing a draft does not retarget that retry. Server author restrictions still apply. Notification read state remains separate from report confirmation/approval.

Verification: new runtime helper tests cover complete/unfinished/manual/empty/route roster eligibility, OFF/dedup zero, unavailable RPC, invalid results, author denial and unknown network outcome followed by same-ID retry. Local Flutter/Dart is unavailable; actual Flutter analysis/tests must pass CI before integration. SQL concurrency/durable receipt coverage remains the existing source notification CI. Physical iPhone notification behavior and production activation remain incomplete.
