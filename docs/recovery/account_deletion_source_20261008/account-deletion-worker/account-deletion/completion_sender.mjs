import {createGmailCompletionMail} from './completion_gmail.mjs';
// Explicitly use the existing support Gmail. No silent fallback to a different
// provider or sender when authorization is missing. No secrets in client builds.
export function createConfiguredCompletionSender({env,fetchImpl=fetch}) {
 if(typeof env!=='function')throw Error('completion_gmail_not_configured');
 return createGmailCompletionMail({
  clientId:env('DELETION_GMAIL_CLIENT_ID'),
  clientSecret:env('DELETION_GMAIL_CLIENT_SECRET'),
  refreshToken:env('DELETION_GMAIL_REFRESH_TOKEN'),fetchImpl,
 });
}
