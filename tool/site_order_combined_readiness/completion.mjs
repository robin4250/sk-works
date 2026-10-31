// Completion evidence is required even when a child runtime exits zero.
export function requireCompletion(output) {
 const receipts = output.split('\n').filter(line => line.startsWith('{')).map(line => JSON.parse(line));
 const required = [
  ['combined_compatibility_installed', receipt => receipt.combined_compatibility_installed === true && receipt.only_six_function_bodies_and_named_check_changed === true && receipt.late_compat_failure_rolled_back === true],
  ['registered_targets_in_full_actual_composition', receipt => receipt.registered_targets_in_full_actual_composition === true && receipt.selected_returned_trade_used_for_prepare === true && receipt.negative_cases === 9],
  ['actual_public_jwt_bodies_and_fixture_live_sid_consumer_smoke', receipt => receipt.actual_public_jwt_bodies_and_fixture_live_sid_consumer_smoke === true && receipt.old_qualification_personnel_read_save_retransfer === true && receipt.mixed_batches_denied_without_mutation === true],
  ['consent_source_only', receipt => receipt.consent_source_only === true && receipt.exact_eight_c_unchanged === true && receipt.actual_public_uid_jwt_bodies === 2],
  ['result', receipt => receipt.result === 'PASS public-reconstructed exact-eight-body fourteen-module composition' && receipt.full_modules === 14 && Number.isInteger(receipt.checks) && receipt.checks >= 315],
 ];
 for (const [kind, predicate] of required) {
  const matching = receipts.filter(receipt => Object.hasOwn(receipt, kind));
  if (matching.length !== 1 || matching[0].production_changed !== false || !predicate(matching[0])) throw Error('missing or ambiguous combined completion evidence');
 }
 return true;
}
