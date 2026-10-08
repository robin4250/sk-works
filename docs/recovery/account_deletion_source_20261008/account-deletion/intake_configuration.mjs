import {deletionPolicy} from './policy.mjs';

// The first deployment connects authentication/status only. A release decision
// after manual erasure acceptance must change this as well as the server flag.
const intakeReleaseVerified = false;
export function intakeConfiguration(env) {
 return {
  enabled: intakeReleaseVerified && env('ACCOUNT_DELETION_ENABLED') === 'true',
  policy: deletionPolicy.version,
  days: deletionPolicy.processingDays,
 };
}
