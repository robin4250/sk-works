# SKO UI/UX decisions — 2026-09-19

This document captures the product decisions made before iPhone device testing.

## Global navigation and notifications

- Use a persistent bottom navigation on general-user screens:
  - Home
  - Attendance sheet
  - Site
  - Chat
  - Menu
- Daily report is not a persistent bottom-navigation item. SKO support should suggest it when relevant.
- The top-right notification bell is visible across major screens.
- Show unread count on the bell.
- Notifications are centralized there; do not duplicate a large "notifications" tile on Home.

## General-user Home

- Header displays registered company/trade name rather than a large SKO brand label.
- Primary daily controls:
  - Today's site selector
  - Register today's attendance
  - Register today's departure
- Useful Home tiles:
  - Payroll statement
  - Profile
  - Site registration
  - Settings
  - Help
- Avoid duplicate tiles for destinations already permanently available in bottom navigation.

## Site selection / leader flow

- A user selects today's work site.
- The user indicates:
  - I am the leader
  - I am not the leader
- A site may have:
  - leader
  - deputy leader
  - temporary leader for the day
- If the regular leader is absent, deputy can take responsibility.
- If both are absent, select a temporary leader from today's members.
- For leader member confirmation, start from the previous workday's member list.
- All previous members are initially checked; leader removes absent workers and confirms.
- This avoids manually selecting a large crew every morning.

## Attendance

### Weekly view

- Month header with previous/next month controls.
- Under the month header show week tabs.
- Number of tabs is 5 or 6 depending on calendar layout.
- Week starts Monday.
- Display exactly Monday through Sunday vertically.
- Dates from previous/next month remain visible in muted gray.
- Main columns:
  - date/day
  - site name
  - small tags for overtime / early start / allowances
  - arrival time
  - departure time
- If a worker did not work that day, show "休み" instead of blank time.
- Do not show redundant "出勤" labels when work times already indicate attendance.
- Remove the large "add attendance" button from the bottom of the attendance sheet.

### Weekly tags

Compact examples:
- 残2 = overtime 2 hours
- 早1 = early start 1 hour
- 鉄1 = steel-work allowance x1
- P1 = PC-related allowance x1

### Monthly calendar

- Calendar icon sits next to notification bell.
- Opens full-month calendar.
- Each worked day shows first 1–2 characters of site name.
- Non-work days show "休".
- Dates outside current month are muted.
- Below calendar show monthly summary:
  - work days
  - overtime hours
  - allowance counts / totals
- Print button below summary.
- Print flow:
  1. A4 preview
  2. print from preview

## Daily report

- Site and worker list are inherited from confirmed attendance/site membership; do not require duplicate entry.
- Daily report focuses on:
  - work description
  - per-worker overtime / early-start / allowance adjustments
  - supervisor signature
- Work-description text area should be larger than the early mockup.
- Each worker may have different overtime/allowance values.

### Signature

- "Sign" action opens full-screen signature pad usable with finger/stylus.
- Report shows a compact state:
  - 未サイン
  - サイン済み
- Tapping "サイン済み" can show actual signature.
- Printed A4 daily report includes the actual signature image.
- Supervisor signature finalizes the daily report and its attendance source data.

### Editing after signature

- Before signature: editable normally.
- After signature: report is confirmed/finalized.
- Editing a finalized report requires approval by 2 authorized sub-admins/admins.
- Requesting edit:
  - sends notifications to approvers
  - requester sees that approval has been requested
- After 2 approvals:
  - requester receives notification
  - edit is temporarily enabled
- Keep complete change/audit history.
- Attendance sheet, monthly totals, allowances, payroll candidates and invoice candidates must derive from corrected daily-report data.
- Do not directly edit finalized attendance/payroll/invoice summaries; correct the daily report source.

## Payroll statement

- Latest statement first.
- Older statements below in vertical scrolling history.
- No "list/detail" toggle needed.
- Show company name first, then worker name.
- Tapping a month opens A4 payroll-statement preview.
- Preview supports pinch zoom.
- Actions include:
  - Print
  - Save PDF

## Chat

- Bottom-nav Chat opens directly into the conversation experience, not an extra landing page.
- Chat top tabs for general users:
  - すべて
  - 現場
  - 個別
- Company-wide duplicate "会社" tab is unnecessary.
- Conversation UI:
  - own messages on right
  - others on left
  - text composer at bottom
  - send button
  - attachment (+/clip) for image/files
- Each conversation supports:
  - Notes
  - Album
- Notes/Albums attach to company/site/direct conversation context.

### Site chat ordering

Priority:
1. Sites where the user has posted/replied recently
2. Sites the user is currently attending
3. Other sites ordered by recent activity

### Direct-chat ordering/search

- Most recent conversation at top.
- Never-contacted people lower down.
- Search field filters as user types.
- Partial input narrows candidates.
- Selecting a result opens direct conversation.
- Designed to remain usable at 100s or 1000s of employees.

### Admin chat

- Admin-only additional tab for partner/contractor companies.
- Ordinary workers do not need cross-company chat.
- Worker-facing cross-company communication is primarily through site guidance/announcements.

## Site screen and downstream company guidance

- Bottom-nav Site shows registered/current sites.
- Site detail can provide "下請け会社へ案内".
- Send registered site information plus comments/meeting instructions to connected contractor companies.
- The recipient gets a bell notification.
- Site guidance may also be retained in relevant site communication history.

## Administrator Home

- Header:
  - company name
  - user name
  - role badge: 管理者 / サブ管理者
  - notification bell top right
- Today's attendance summary distinguishes:
  - own-company workers
  - contractor-company workers
  - total
- Rename ambiguous "未確認" to "承認待ち".
- Home tiles are permission-driven.
- Example admin-only financial tiles:
  - 請求書
  - 管理者用現場データ
- Sub-admin sees only allowed actions.
- A sole proprietor can combine admin and worker actions, including attendance/departure.

## Personnel management / permissions

- Personnel list includes:
  - owner/admin
  - sub-admins
  - ordinary workers
  - contractor companies/workers as applicable
- Open a person to configure:
  - role
  - permissions
  - home-visible functions
- Unauthorized functions are hidden, not merely disabled.
- Settings remains for application/company settings; personnel permissions belong in Personnel management.

## Admin attendance / man-day management

- Tabs/filters:
  - daily
  - by employee
  - by site
- Site name is the primary grouping instead of redundant "出勤" text.
- Daily site drill-down shows:
  - site
  - counts (own company / contractor / total)
  - members
  - arrival/departure times

## Invoice management

- Sensitive; requires secondary authentication.
- Default list is read-oriented; source amounts come from finalized operational data.
- Month navigation:
  - current month label
  - previous/next arrows
- Tabs/modes include:
  - 一覧
  - 会社別
  - 確定済み as applicable
- Company mode:
  - choose registered customer/transaction company from dropdown
  - show matching invoices below
- Support Month / Year view.
- Year view can export all months.
- Invoice actions:
  - A4 preview
  - print
  - email
  - save PDF to device
- Year export:
  - save/print/email all year
  - optionally one combined file or month-separated output
- Invoice configuration has a dedicated settings screen for:
  - template
  - tax rate
  - statutory welfare rate
  - bank transfer destination
  - other company defaults

## Administrator-only site financial data

- Call the sensitive section "管理者用現場データ" to avoid confusion with ordinary Site screens.
- Requires secondary authentication.
- Stores/administers financial/contract data such as:
  - standard unit/man-day rate
  - contract amount
  - statutory welfare rate
  - transport/accommodation/other confidential cost settings
- Only authorized administrators may view/edit.
- Operational Site screen remains separate for ordinary staff.

## Authentication / secondary lock

### Primary registration

Admin:
1. phone number as ID
2. main password
3. main password confirmation
4. SMS OTP

Existing legacy email accounts remain supported.

### Secondary sensitive-data password

Immediately after account verification:
1. explain why sensitive-data protection is required
2. secondary password
3. secondary password confirmation
4. optional Face ID / Touch ID

SMS OTP is not repeated for the secondary password.

Sensitive areas require separate unlock even while app is already logged in.

Current first protected area:
- invoices

Planned protected areas:
- 管理者用現場データ
- other confidential finance/payroll screens

## Guiding product rule

SKO should feel understandable to a user who can already use LINE. Common actions should be obvious, large, rounded, and close to the next action the user is likely to want.
