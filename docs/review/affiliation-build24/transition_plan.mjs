// Offline planning only. Never authorizes, schedules, or changes an account.
// Every evidence reference must be minted and rechecked by the future server.
const directions = new Set(['employee_to_representative', 'representative_to_employee']);
const reference = value => typeof value === 'string' && /^[A-Za-z0-9_-]{1,160}$/.test(value);
export function planAffiliationTransition(input) {
  if (!input || !directions.has(input.direction)) throw new Error('invalid_direction');
  for (const key of ['requestId','actorId','subjectId','personalSkoId','sourceCompanyId','targetCompanyId','sourceWorkerId','partnerRegistrationId']) {
    if (!reference(input[key])) throw new Error('invalid_reference');
  }
  if (input.sourceCompanyId === input.targetCompanyId) throw new Error('same_company');
  if (typeof input.linkCompanies !== 'boolean') throw new Error('invalid_link_choice');
  // Require a date-only Gregorian date; Japan effective-date processing is server-owned.
  const day = input.effectiveDate;
  if (typeof day !== 'string' || !/^20\d{2}-\d{2}-\d{2}$/.test(day) ||
      !Number.isFinite(Date.parse(day)) || new Date(day).toISOString().slice(0,10) !== day) throw new Error('invalid_date');
  const e = input.evidence;
  for (const key of ['identityConsent','sourceAdministrator','companyMatch','representativeAuthority','personalArchive']) {
    if (!e || !reference(e[key])) throw new Error('missing_evidence');
  }
  if (input.flags?.affiliation_switch !== true || input.flags?.sko_id_linking !== true || input.flags?.personal_pdf_vault !== true) throw new Error('feature_off');
  if (input.linkCompanies && input.flags?.partner_auto_link !== true) throw new Error('company_link_off');
  if (input.direction === 'representative_to_employee' && input.flags?.company_lifecycle !== true) throw new Error('lifecycle_off');
  const effects = [
    'recheck_live_session_and_evidence', 'lock_subject_and_both_companies',
    'confirm_personal_pdf_archive_receipts', 'append_membership_history',
    input.direction === 'employee_to_representative' ? 'grant_verified_representative_membership' : 'suspend_old_company_and_restore_employee_membership',
    'invalidate_old_permission_context', 'record_atomic_receipt',
  ];
  if (input.linkCompanies) effects.splice(-2,0,'request_existing_company_link_and_deduplicate_trade_registration');
  return Object.freeze({
    schema:1, requestId:input.requestId, subjectId:input.subjectId, personalSkoId:input.personalSkoId,
    sourceCompanyId:input.sourceCompanyId, targetCompanyId:input.targetCompanyId,
    effectiveDate:day, direction:input.direction, effects:Object.freeze(effects),
    preserve:Object.freeze(['auth_user_id','personal_sko_id','source_worker_id','source_attendance','source_payroll','source_company_documents']),
    forbidden:Object.freeze(['create_new_sko_id','copy_old_payroll_into_target_company','copy_other_worker_data','delete_old_company','publish_documents_on_link']),
  });
}
