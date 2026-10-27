import test from 'node:test';
import assert from 'node:assert/strict';
import {planAffiliationTransition as plan} from './transition_plan.mjs';
const fixture = () => ({direction:'employee_to_representative',requestId:'request1',actorId:'admin1',subjectId:'person1',personalSkoId:'existing-id',sourceCompanyId:'company1',targetCompanyId:'company2',sourceWorkerId:'worker1',partnerRegistrationId:'partner1',effectiveDate:'2026-11-01',linkCompanies:false,flags:{affiliation_switch:true,sko_id_linking:true,personal_pdf_vault:true,partner_auto_link:true,company_lifecycle:true},evidence:{identityConsent:'proof1',sourceAdministrator:'proof2',companyMatch:'proof3',representativeAuthority:'proof4',personalArchive:'proof5'}});
test('same identity is retained and no historical records are transferred',()=>{
  const p=plan(fixture()); assert.equal(p.personalSkoId,'existing-id');
  assert.ok(p.preserve.includes('source_payroll')); assert.ok(p.forbidden.includes('copy_old_payroll_into_target_company'));
  assert.ok(!p.effects.some(x=>x.includes('deduplicate')));
});
test('YES requests existing link without publishing documents',()=>{
  const p=plan({...fixture(),linkCompanies:true});
  assert.ok(p.effects.includes('request_existing_company_link_and_deduplicate_trade_registration'));
  assert.ok(p.forbidden.includes('publish_documents_on_link'));
});
test('reverse direction suspends company and preserves its records',()=>{
  const p=plan({...fixture(),direction:'representative_to_employee'});
  assert.ok(p.effects.includes('suspend_old_company_and_restore_employee_membership'));
  assert.ok(p.forbidden.includes('delete_old_company'));
});
test('missing checks and unavailable switches fail closed',()=>{
  for(const key of Object.keys(fixture().evidence)){const x=fixture();delete x.evidence[key];assert.throws(()=>plan(x),/missing_evidence/);}
  for(const key of ['affiliation_switch','sko_id_linking','personal_pdf_vault']){const x=fixture();x.flags[key]=false;assert.throws(()=>plan(x),/feature_off/);}
  assert.throws(()=>plan({...fixture(),linkCompanies:true,flags:{...fixture().flags,partner_auto_link:false}}),/company_link_off/);
  assert.throws(()=>plan({...fixture(),direction:'representative_to_employee',flags:{...fixture().flags,company_lifecycle:false}}),/lifecycle_off/);
});
test('invalid dates, ambiguous choices and same company are rejected',()=>{
  for(const effectiveDate of ['2026-02-30','2026-11-01T00:00:00Z','bad'])assert.throws(()=>plan({...fixture(),effectiveDate}),/invalid_date/);
  assert.throws(()=>plan({...fixture(),targetCompanyId:'company1'}),/same_company/);
  assert.throws(()=>plan({...fixture(),linkCompanies:'YES'}),/invalid_link_choice/);
});
