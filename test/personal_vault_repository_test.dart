import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/personal_vault/personal_vault_repository.dart';
void main() {
 final row = {'manifest_id':'10000000-0000-0000-0000-000000000001',
  'artifact_key':'a'*64,'kind':'own_attendance',
  'source_company_id':'20000000-0000-0000-0000-000000000001',
  'completed_at':'2026-10-27T00:00:00Z'};
 test('completed receipt list parses and malformed/duplicate responses fail closed', () {
  expect(PersonalVaultRepository.parseMine([row]).single.label,'本人出勤表');
  expect(()=>PersonalVaultRepository.parseMine([row,row]),throwsFormatException);
  expect(()=>PersonalVaultRepository.parseMine([{
   ...row,'kind':'company_internal'}]),throwsFormatException);
  expect(()=>PersonalVaultRepository.parseMine(null),throwsFormatException);
 });
}
