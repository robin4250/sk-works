// Server-only. Credentials must come from a trusted, subject-bound store.
// Never use the completion-mail OAuth client or mailbox refresh token here.
const tokenUrl = 'https://oauth2.googleapis.com/token';
const userUrl = 'https://openidconnect.googleapis.com/v1/userinfo';
const revokeUrl = 'https://oauth2.googleapis.com/revoke';
const nonempty = value => typeof value === 'string' && value.length > 0 &&
 value.length <= 8192 && !/[\x00-\x20\x7f]/.test(value);

export function createGoogleIdentityRevocation({clientId, clientSecret, readCredential, revocationEvidence, fetchImpl = fetch}) {
 if (!nonempty(clientId) || !clientId.endsWith('.apps.googleusercontent.com') ||
     !nonempty(clientSecret) || typeof readCredential !== 'function')
  throw Error('google_revocation_not_configured');
 if(revocationEvidence!==undefined &&
    (typeof revocationEvidence.read!=='function'||typeof revocationEvidence.write!=='function'))
  throw Error('google_revocation_evidence_not_configured');
 const request = (url, options) => fetchImpl(url, {
  ...options, redirect: 'error', signal: AbortSignal.timeout(10000),
 });
 const form = (url, values) => request(url, {
  method: 'POST', headers: {'Content-Type': 'application/x-www-form-urlencoded'},
  body: new URLSearchParams(values).toString(),
 });
 const refresh = token => form(tokenUrl, {
  client_id: clientId, client_secret: clientSecret,
  grant_type: 'refresh_token', refresh_token: token,
 });
 const userInfo = token => request(userUrl, {
  method: 'GET', headers: {Authorization: `Bearer ${token}`},
 });
 const inspect = async (job, identity) => {
  if (identity?.provider !== 'google' || !nonempty(identity.id) ||
      !nonempty(identity.identity_data?.sub) || !nonempty(job?.id) || !nonempty(job.userId))
   throw Error('google_identity_unconfirmed');
  const credential = await readCredential({jobId: job.id, userId: job.userId, identityId: identity.id,leaseToken:job.leaseToken});
  if (!credential || credential.jobId !== job.id || credential.userId !== job.userId ||
      credential.identityId !== identity.id || credential.clientId !== clientId ||
      !nonempty(credential.refreshToken)) throw Error('google_credential_unconfirmed');
  // Refreshing with the configured sign-in client binds the token to that client.
  const response = await refresh(credential.refreshToken);
  // A response/checkpoint can be lost AFTER Google revoked the grant. Only a
  // durably stored, previously subject-verified pair may prove that retry safe.
  if(response.status===400 && revocationEvidence &&
     (await response.json()).error==='invalid_grant') {
   const prior=await revocationEvidence.read(job,identity);
   if(!prior || prior.jobId!==job.id || prior.userId!==job.userId ||
      prior.identityId!==identity.id || prior.clientId!==clientId ||
      prior.planDigest!==job.reviewedPlanDigest || prior.googleSubject!==identity.identity_data.sub ||
      prior.refreshToken!==credential.refreshToken || !nonempty(prior.accessToken))
    throw Error('google_revocation_evidence_unconfirmed');
   if((await userInfo(prior.accessToken)).status!==401)throw Error('google_revocation_unconfirmed');
   return {alreadyRevoked:true};
  }
  if (response.status !== 200) throw Error('google_credential_unconfirmed');
  const token = await response.json();
  if (!nonempty(token.access_token) || token.token_type?.toLowerCase() !== 'bearer')
   throw Error('google_credential_unconfirmed');
  const profileResponse = await userInfo(token.access_token);
  if (profileResponse.status !== 200 || (await profileResponse.json()).sub !== identity.identity_data.sub)
   throw Error('google_identity_unconfirmed');
  return {refreshToken: credential.refreshToken, accessToken: token.access_token};
 };
 const revoke = async (job, identity) => {
  try {
   const token = await inspect(job, identity);
   if(token.alreadyRevoked===true)return true;
   if(revocationEvidence && await revocationEvidence.write(job,identity,token)!==true)
    throw Error('google_revocation_evidence_unconfirmed');
   const response = await form(revokeUrl, {token: token.refreshToken});
   if (response.status !== 200) throw Error('google_revocation_unconfirmed');
   // Acceptance is not immediate invalidation. Any lag/outage stops erasure.
   if ((await userInfo(token.accessToken)).status !== 401)
    throw Error('google_revocation_unconfirmed');
   const refreshed = await refresh(token.refreshToken);
   if (refreshed.status !== 400 || (await refreshed.json()).error !== 'invalid_grant')
    throw Error('google_revocation_unconfirmed');
   return true;
  } catch (_) {
   // Do not expose request bodies, provider errors, tokens, or profile details.
   throw Error('google_revocation_unconfirmed');
  }
 };
 // Eligibility check before restricting account access; repeats at execution.
 revoke.inspect = async (job, identity) => {
  try { await inspect(job, identity); return true; }
  catch (_) { throw Error('google_credential_unconfirmed'); }
 };
 return revoke;
}
