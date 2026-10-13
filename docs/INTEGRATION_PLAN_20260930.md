# SKO Integration Plan — 2026-09-30

This document is the integration map for the decisions made before the next TestFlight candidate. Implement in small green-CI slices; do not reconnect features ad hoc.

## 1. Shared product rules

- SKO home-style, friendly, large-tap-target UI.
- Use ? help only where a first-time user may hesitate.
- Registration, edit, disable, approval, rejection, permission and inter-company send actions require a confirmation step.
- Preserve history: operational records are disabled/archived rather than physically deleted where historical references exist.

## 2. International architecture

- One SKO app, not country-forked copies.
- Shared core + Country Pack + Language Pack.
- Japan is the first production pack under countries/jp and languages/ja.
- Device locale suggests first-run language/region; it never permanently decides country.
- Unsupported/malformed selections fall back safely without blocking startup.
- Move Japan-specific phone, currency, date, holidays, address, tax/legal/document rules incrementally with CI after each slice.

## 3. Master administration

- Master entry requires master role + trusted device + biometric/Face ID + master second password.
- Step-up session expires and clears on app exit.
- Master analytics collects aggregate operational numbers, not chat/file/photo/password/OTP content.
- Dashboard targets: company/user/connection totals, 7/30-day growth, members/company avg-min-max, feature/page/button usage, storage usage.
- Master controls include reversible vehicle and route feature availability.

## 4. Company identity and connection

- SKO company ID is visible read-only to every employee on Profile/My Page.
- Personal SKO ID remains hidden until a future service needs it.
- Company discovery keys: company name, address, corporate number, SKO company ID.
- Discovery never grants access; request + acceptance is required.

## 5. People / qualification / document hierarchy

Information scope:
1. Personnel bundle = basic person data + qualifications + documents.
2. Qualification send/print = qualifications only.
3. Document send/print = documents only.

Required UI:
- People list: send to parent company + print.
- Qualification list: send to parent company + print.
- Document list: send to parent company + print.
- Person detail: basic data, linked qualifications and linked documents; send/print whole bundle or scoped sections.
- List actions support multi-select.
- Every send shows target company, people and payload before final confirmation.

## 6. Subcontractor folder and forwarding

- Received lower-tier data is grouped under subcontractor company folders.
- Preserve origin company and forwarding provenance.
- Received personnel/qualification/document payload can be forwarded upward without re-entry/re-upload.
- A chain such as C -> B -> A remains traceable at A.
- Forwarding uses the same confirmation flow as an original send.

## 7. Site and site-chat lifecycle

- Site registration creates exactly one site chat.
- A worker automatically joins on first recorded attendance at that site.
- Owner/admin/sub-admin may enter for operational oversight without attendance.
- Shared parent-company sites become usable by connected lower companies; do not auto-add every employee.
- Site chat card may show name, address, nearest station and period.
- Never expose site unit price, billing customer or other admin/financial fields to chat.
- Site closure archives chat/history instead of deleting it.

## 8. Vehicle and route management

- All company employees can use active vehicles/routes when the company module is ON.
- Only owner/admin/sub-admin may create, edit, disable, or register vehicle/route master data.
- Admin can turn the entire vehicle/route module ON/OFF; OFF removes its home/menu/daily-work-report entry points.
- Use soft-disable to preserve historical attendance/route references.
- Vehicle: display name, registration number, odometer, vehicle inspection certificate, compulsory insurance, voluntary insurance.
- Vehicle documents accept PDF, photo library images, or camera capture and are stored in private Storage.
- Route: route name, unlimited ordered stops where each stop is either a selected site or an address, plus notes.
- Daily work report exposes a vehicle/route selector below the attendance-method/site selector. Each can be cleared to unselected.
- Selected vehicle/route is copied into clock-in/out records and daily report worker rows.
- If a vehicle is selected at clock-out, daily report entry exposes odometer camera OCR, confirmation/retry/manual correction, then updates the vehicle odometer on save.
- Daily report A4 output prints selected vehicle, route, and odometer.
- New pages follow shared SKO UI and confirmation rules.
- Master page exposes vehicle/route status and reversible feature controls.

## 9. Future high-grade edition

Video meetings are not part of the current standard/TestFlight scope.
Preserve extension points for:
- 1-to-1 video calls.
- Group video meetings.
- Site/project video meetings.
- Company/team meetings.
- Provider-neutral media interface so chat is not rebuilt when providers change.
- Recording only as a later explicit-consent, country-aware feature.

## 10. Integration order

1. Merge already-green isolated foundations.
2. Finish company data-transfer contract and site-chat lifecycle contracts.
3. Build people/qualification/document shared send-print UI.
4. Connect subcontractor receive/forward folders.
5. Connect site registration -> chat creation -> attendance auto-join.
6. Build vehicle/route persistence and RLS.
7. Build vehicle/route friendly UI and delegated permissions.
8. Add master dashboard buttons/metrics for new modules.
9. Continue Japan-specific migration into country/language packs in behavior-preserving slices.
10. Run full TestFlight regression/security/device gates.

Each step must leave main buildable and must not bypass failed CI/security checks.
