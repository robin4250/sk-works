// Operator-approved on 2026-09-26. Approval does not enable the unfinished worker.
export const deletionPolicy = Object.freeze({
  version: '2026-09-26-company-records-retained-v1',
  processingDays: 30,
  retainedCompanyRecords: Object.freeze(['payroll', 'invoices', 'signed_daily_reports']),
  // Operator decision: SKO is the company's official document store.
  // This confirms storage purpose, not a blanket retention period or erasure.
  companyDocumentStorage: 'official-records',
  officialDocumentRetentionFinalized: false,
});

// These buckets mix health/qualification/identity records and related copies.
// Until per-record classification and retention are implemented, no object in
// them may pass the generic personal-file eraser, even with ownership verified.
export const officialDocumentReviewBuckets = Object.freeze([
  'worker-documents',
  'qualification-certificates',
  'employee-onboarding-documents',
]);
