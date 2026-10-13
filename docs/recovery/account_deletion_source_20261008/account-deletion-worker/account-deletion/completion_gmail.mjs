// Server-only Gmail API transport for the existing SKO support mailbox.
// Requires an operator-authorized gmail.send refresh token, not a Gmail password.
// No automatic retries: Gmail has no send idempotency guarantee. The persistent
// notice reservation must prevent a second send after an ambiguous response.
const sender='sko.support@gmail.com';
const email=/^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?\.[A-Za-z]{2,}$/;
const base64=s=>{
 const bytes=new TextEncoder().encode(s);
 let binary=''; for(const b of bytes) binary+=String.fromCharCode(b);
 return btoa(binary);
};
const wrappedBase64=s=>base64(s).match(/.{1,76}/g)?.join('\r\n')??'';
const encodeSubject=s=>Array.from(s).reduce((parts,char)=>{
 if(!parts.length || new TextEncoder().encode(parts.at(-1)+char).length>42)parts.push(char);
 else parts[parts.length-1]+=char;
 return parts;
},[]).map(s=>`=?UTF-8?B?${base64(s)}?=`).join('\r\n ');
export function createGmailCompletionMail({clientId,clientSecret,refreshToken,fetchImpl=fetch,now=()=>new Date()}) {
 if(![clientId,clientSecret,refreshToken].every(v=>typeof v==='string'&&v.trim()))
  throw Error('completion_gmail_not_configured');
 return async ({to,idempotencyKey,subject,text})=>{
  if(typeof to!=='string'||to.length>254||!email.test(to)||typeof subject!=='string'||
   !subject.length||subject.length>500||/[\r\n]/.test(subject)||typeof text!=='string'||text.length>10000||
   typeof idempotencyKey!=='string'||!/^account-deletion\/[0-9a-f-]{36}$/i.test(idempotencyKey))
   throw Error('invalid_completion_message');
  try {
   const tokenResponse=await fetchImpl('https://oauth2.googleapis.com/token',{
    method:'POST',signal:AbortSignal.timeout(10000),headers:{'Content-Type':'application/x-www-form-urlencoded'},
    body:new URLSearchParams({client_id:clientId,client_secret:clientSecret,refresh_token:refreshToken,grant_type:'refresh_token'}).toString(),
   });
   if(!tokenResponse.ok)throw Error('authorization_unconfirmed');
   const token=await tokenResponse.json();
   if(typeof token.access_token!=='string'||!token.access_token||/[\r\n]/.test(token.access_token))throw Error('authorization_unconfirmed');
   const message=[`From: SKO JAPAN <${sender}>`,`To: ${to}`,
    `Subject: ${encodeSubject(subject)}`,`Date: ${now().toUTCString()}`,
    `Message-ID: <sko-${idempotencyKey.split('/')[1]}@gmail.com>`,
    'MIME-Version: 1.0','Content-Type: text/plain; charset=UTF-8','Content-Transfer-Encoding: base64','',wrappedBase64(text),''].join('\r\n');
   // Bind the API user as well as the From header. Authorization for a different
   // mailbox must fail instead of silently rewriting the sender.
   const response=await fetchImpl(`https://gmail.googleapis.com/gmail/v1/users/${encodeURIComponent(sender)}/messages/send`,{
    method:'POST',signal:AbortSignal.timeout(10000),headers:{Authorization:`Bearer ${token.access_token}`,'Content-Type':'application/json'},
    body:JSON.stringify({raw:base64(message).replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,'')}),
   });
   if(!response.ok)throw Error('send_unconfirmed');
   const data=await response.json();
   if(typeof data.id!=='string'||!/^[A-Za-z0-9_-]{1,200}$/.test(data.id))throw Error('send_unconfirmed');
   // API acceptance only. Actual inbox delivery remains a separate check.
   return {id:data.id};
  }catch(_){throw Error('completion_delivery_unconfirmed');}
 };
}
