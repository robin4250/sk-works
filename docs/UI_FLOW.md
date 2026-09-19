# SKO friendly UI flow

This document defines the user-facing screen order before device testing.

## Design principles

- A person who can use LINE should be able to use SKO without training.
- Prefer large rounded tap targets, plain Japanese, and one obvious next action.
- Keep business terminology out of worker-facing screens unless it is unavoidable.
- Do not force users to search a long menu for common actions.
- After a user finishes one task, surface the next likely task.
- Admin and worker experiences share the same visual language but show different priorities.

## Worker flow

### W-1 My page
Top to bottom:
1. Friendly welcome / today's status
2. SKO support card with the most likely next action
3. Large buttons: attendance confirmation, attendance sheet, qualifications, required documents
4. Chat
5. Suggested flow
6. Personal information shortcuts

### W-2 Attendance confirmation
Three company-selectable modes:
1. Manual only
2. Location
3. Location + photo

Capture location/photo only when the worker explicitly confirms attendance or departure.

### W-3 Attendance sheet
Use a calendar/list hybrid with:
- worked / absent / corrected state
- total worked days prominently shown
- overtime/allowance summary when available
- a next-action link to payroll statement when payroll is implemented

### W-4 Payroll statement
Simple, conventional payroll-statement layout:
- pay period
- gross pay
- deductions
- net pay prominently
- expandable detail rows
- next-action link back to attendance sheet

This is a display target. Payroll calculation is not yet implemented in the current codebase.

### W-5 Chat
Keep the interaction model familiar:
- group list
- conversation screen
- bottom composer
- image attachment
- unread emphasis
Avoid copying proprietary branding/assets.

## Admin flow

### A-1 Admin home
Top to bottom:
1. Today's attention card
2. Large buttons: people, sites, attendance, invoices
3. Chat
4. Suggested admin sequence
5. Documents, qualification certificates, rollout readiness, settings

### A-2 People
Prioritize:
- worker name/company
- active status
- missing/expired document warning
- qualification warning
- site assignment shortcut

### A-3 Attendance management
Show:
- today confirmed / unconfirmed / correction-needed counts
- site filter
- worker filter
- verification method badge
- correction audit trail

### A-4 Invoice
Conventional business layout:
- customer and period
- site totals
- adjustments
- tax
- grand total prominently
Keep on-screen totals consistent with printed/exported output.

### A-5 Company relationship / collaboration
For parent / partner / downstream company relationships:
- clear relationship status
- who requested the connection
- what data is shared
- approve / reject / disconnect actions
- never imply that connecting companies merges their private internal data

## Guided next actions

Examples:
- attendance confirmed -> suggest daily report / attendance sheet
- attendance sheet viewed -> suggest payroll statement
- payroll statement viewed -> suggest attendance sheet for detail
- admin sees missing attendance -> suggest worker/site review
- invoice draft reviewed -> suggest final validation rather than automatic sending

The guidance should assist, not block. Users can always navigate directly.
