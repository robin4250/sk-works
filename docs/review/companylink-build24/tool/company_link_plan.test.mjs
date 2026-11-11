import { test } from 'node:test';
import assert from 'node:assert/strict';
import { planCompanyLink } from './company_link_plan.mjs';
const a='00000000-0000-0000-0000-000000000001',b='00000000-0000-0000-0000-000000000002',c='00000000-0000-0000-0000-000000000003';
const input=()=>({linkRequested:true,sourceCompany:{id:a,name:'Canonical',corporateNumber:'1234567890123'},targetCompany:{id:b},selectedPartner:{id:c,companyId:a,linkedCompanyId:b},reciprocalDirectory:[],existingRequests:[],connections:[]});
test('YES requests existing approval; never creates company or exposes documents',()=>{
 const p=planCompanyLink(input()); assert.equal(p.kind,'request_reciprocal_approval');assert.equal(p.createCompany,false);assert.equal(p.discloseDocuments,false);
});
test('NO only switches affiliation; requires verified existing partner',()=>{
 const i=input();i.linkRequested=false;assert.equal(planCompanyLink(i).kind,'affiliation_only');i.selectedPartner.linkedCompanyId=null;assert.throws(()=>planCompanyLink(i));
});
test('existing identity wins and contact details never copied into plan',()=>{
 const i=input();i.reciprocalDirectory=[{id:c,companyId:b,linkedCompanyId:a,role:'customer',phone:'private'}];i.connections=[{parentId:a,childId:b,status:'accepted'}];
 assert.equal(planCompanyLink(i).kind,'already_linked');assert.equal(JSON.stringify(planCompanyLink(i)).includes('private'),false);
});
test('corporate number may select existing entry; name alone never merges',()=>{
 const i=input();i.reciprocalDirectory=[{id:c,companyId:b,corporateNumber:'1234567890123',role:'subcontractor'}];assert.equal(planCompanyLink(i).reciprocalDirectoryId,c);
 i.reciprocalDirectory=[{id:c,companyId:b,name:'Canonical'}];assert.throws(()=>planCompanyLink(i),/unverified_same_name/);
});
test('duplicate identity or corporate number rejects instead of making another entry',()=>{
 const i=input();i.reciprocalDirectory=[1,2].map(()=>({id:c,companyId:b,linkedCompanyId:a}));assert.throws(()=>planCompanyLink(i),/duplicate_linked/);
 i.reciprocalDirectory=[1,2].map(()=>({id:c,companyId:b,corporateNumber:'1234567890123'}));assert.throws(()=>planCompanyLink(i),/duplicate_corporate/);
});
test('pending pair is reused without extra request',()=>{
 const i=input();i.existingRequests=[{senderId:b,targetId:a,status:'pending'}];assert.equal(planCompanyLink(i).kind,'reuse_pending_request');
 i.existingRequests.push(i.existingRequests[0]);assert.throws(()=>planCompanyLink(i),/duplicate_pending/);
});
test('foreign scope, missing choice and self link fail closed',()=>{
 const i=input();i.reciprocalDirectory=[{id:c,companyId:a}];assert.throws(()=>planCompanyLink(i),/scope/);
 i.reciprocalDirectory=[];i.linkRequested=null;assert.throws(()=>planCompanyLink(i),/explicit_choice/);
 i.linkRequested=true;i.targetCompany.id=a;assert.throws(()=>planCompanyLink(i),/invalid_company/);
});
