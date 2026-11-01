import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/payroll_insurance_basis_reference.dart';
void main(){
 const scope={'p_company_id':'company','p_worker_id':'worker'};
 Map<String,dynamic> state()=>{'company_id':'company','worker_id':'worker','items':[],'can_edit':true};
 test('personal source top marker survives supported full insurance reader without touching stored values',()async{
  final base={...state(),'insurance_basis_reference_contract_version':1,'birth_source':'personal_uid_v1'};
  final full={...state(),'insurance_basis_reference_contract_version':1};
  final result=await readPayrollTaxConditionsWithInsuranceReference((name,_)async=>name=='read_worker_payroll_tax_conditions'?base:full,scope);
  expect(result['birth_source'],'personal_uid_v1');expect(full.containsKey('birth_source'),false);
  expect(result['items'],full['items']);
 });
 test('missing source is preparation, unknown source or conflicting full declaration rejects',()async{
  expect(payrollUsesPersonalBirthSource(state()),false);
  for(final value in [null,true,1,'company_dob','personal_uid_v2']){
   expect(()=>payrollUsesPersonalBirthSource({...state(),'birth_source':value}),throwsFormatException);
  }
  await expectLater(readPayrollTaxConditionsWithInsuranceReference((name,_)async=>{
   ...state(),'insurance_basis_reference_contract_version':1,
   if(name!='read_worker_payroll_tax_conditions')'birth_source':'personal_uid_v1',
  },scope),throwsFormatException);
 });
 test('unlinked company source remains explicit through full reader and conflicts reject',()async{
  final raw={...state(),'insurance_basis_reference_contract_version':1,'birth_source':'company_worker_unlinked_v1'};
  final full={...state(),'insurance_basis_reference_contract_version':1};
  final result=await readPayrollTaxConditionsWithInsuranceReference((name,_)async=>name=='read_worker_payroll_tax_conditions'?raw:full,scope);
  expect(payrollBirthSource(result),'company_worker_unlinked_v1');expect(payrollUsesPersonalBirthSource(result),false);
  await expectLater(readPayrollTaxConditionsWithInsuranceReference((name,_)async=>name=='read_worker_payroll_tax_conditions'?raw:{...full,'birth_source':'personal_uid_v1'},scope),throwsFormatException);
 });
}
