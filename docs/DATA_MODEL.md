# SK WORKS Initial Data Model

This document defines the first production-oriented data model. Field names can evolve, but the relationships should remain stable.

## Company

- id
- name
- postal_code
- address
- phone
- invoice_registration_number
- bank/payment settings
- created_at / updated_at

## Customer

- id
- name
- billing_name
- billing_address
- closing_day
- payment_terms
- invoice_detail_mode
- separate_invoice_required
- tax/welfare defaults
- notes

`invoice_detail_mode` values:

- `consolidated_only`
- `site_breakdown_on_invoice`
- `site_breakdown_attachment`

## PartnerCompany

- id
- name
- contact information
- status
- notes

## Worker

- id
- affiliation_type (`employee` or `partner_company`)
- partner_company_id when applicable
- name
- kana
- phone
- status
- notes

## QualificationMaster

- id
- name
- category
- expiry_required
- notes

## WorkerQualification

- id
- worker_id
- qualification_master_id
- certificate_number
- issued_at
- expires_at
- issuer
- attachment reference (later phase)
- notes

## Site

- id
- customer_id
- name
- address
- starts_at / ends_at
- manager_worker_id
- status
- notes

## SiteWorkerAssignment

- id
- site_id
- worker_id
- role
- starts_at / ends_at

## AttendanceEntry

- id
- date
- worker_id
- site_id
- base_man_days
- regular_hours
- overtime_hours
- early_hours
- night_hours
- allowance_amount
- notes
- created_by / updated_by (backend phase)

## Invoice

Represents one customer-period invoice unless the customer explicitly requires separate invoices.

- id
- customer_id
- billing_period_start
- billing_period_end
- invoice_number
- issue_date
- due_date
- status
- subtotal
- tax
- welfare_amount
- adjustments
- grand_total
- detail_mode snapshot
- notes

## InvoiceSiteCalculation

A child calculation for each site included in an invoice.

- id
- invoice_id
- site_id
- calculation_method
- quantity_or_man_days
- unit_price
- overtime_amount
- early_amount
- night_amount
- allowance_amount
- lump_sum_amount
- additional_work_amount
- manual_adjustment_amount
- subtotal
- tax setting/snapshot
- welfare setting/snapshot
- notes

## InvoiceDetailLine

Used when detailed continuation or attachment sheets are required.

- id
- invoice_site_calculation_id
- date/description
- worker reference when applicable
- quantity
- unit
- unit_price
- amount
- category
- sort_order

## Relationship summary

- Customer 1 -> many Sites
- Customer 1 -> many Invoices
- Site 1 -> many AttendanceEntries
- Worker 1 -> many AttendanceEntries
- Worker 1 -> many WorkerQualifications
- Invoice 1 -> many InvoiceSiteCalculations
- InvoiceSiteCalculation 1 -> many InvoiceDetailLines

The key invoice rule is that many site calculations can roll up into one customer-period invoice without losing the site-level detail needed for customer-specific output.
