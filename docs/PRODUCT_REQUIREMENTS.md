# SK WORKS Product Requirements

## Purpose

SK WORKS is an operations app for construction-related company management. It should connect people, partner companies, qualifications, sites, attendance/man-days, and invoicing so information entered once can be reused throughout the workflow.

## Core modules

### 1. Employees and partner companies

- Register employees, subcontractors/partner companies, and their workers.
- Store contact and employment/affiliation information.
- Link each person to qualifications, sites, attendance, and billing-related records where applicable.
- Support active/inactive status instead of destructive deletion for production data.

### 2. Qualification management

- Maintain a qualification master so qualifications are registered consistently.
- Register qualifications held by employees and partner-company workers.
- Support certificate number, issue date, expiry date when applicable, issuer, notes, and document/photo attachment in a later phase.
- Make qualification registration fast enough to use while entering many workers.

### 3. Site/project management

- Register site name, customer, address, period, responsible person, status, notes, and participating workers/partner companies.
- Link site records to attendance/man-days and invoice calculations.
- Allow one customer to have many sites in the same billing period.

### 4. Attendance and man-day tracking

- Record date, worker, site, base man-days/hours, overtime, early work, night work, allowances, and notes as needed.
- Keep source attendance/man-day data reusable for invoice calculations.
- Support corrections while preserving an audit-friendly history in the production backend phase.

### 5. Invoice management

The default upstream invoice is consolidated by customer/company and billing period.

Some customers/projects require site-by-site calculations and supporting detail. Therefore each site must be able to hold its own calculation basis, including as applicable:

- quantities/man-days
- unit prices
- overtime
- early work
- night work
- allowances
- lump-sum work
- additional work
- manual adjustments
- subtotal
- tax settings
- welfare-related settings
- supporting detail

Site calculations roll up into the customer's consolidated invoice grand total.

Customer invoice settings must support these detail modes:

1. Consolidated-only invoice.
2. Site-by-site calculation shown directly on the invoice.
3. Site-specific calculation/detail shown on attached or continuation sheets.

Even when site-specific calculation is required, the customer-period invoice remains one invoice unless the customer explicitly requires separate invoices.

Multi-page output should continue the same invoice rather than incorrectly creating separate invoices.

### 6. Settings and master data

- Company information.
- Customers.
- Partner companies.
- Qualification master.
- Billing rules/templates by customer.
- Tax and welfare-related settings.
- Standard unit prices and allowance definitions where useful.

## Data and security direction

The current Flutter prototype uses local device storage only for development convenience. Production should move business-critical data to an authenticated backend with access control, backups, auditability, and document storage.

Sensitive or important company records must not rely on simple device preferences as the final database.

## Product principles

- Enter information once and reuse it.
- Keep common daily operations fast on iPhone.
- Prefer structured master data over repeated free-text entry.
- Preserve customer-specific invoice rules without making every customer a separate application flow.
- Avoid destructive changes to financially or operationally important historical records.
