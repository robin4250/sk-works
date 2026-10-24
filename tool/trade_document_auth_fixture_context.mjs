// In-process handoff for the dedicated loopback GoTrue setup runner only.
let context;
export function installTradeDocumentAuthContext(value){
 if(context||process.env.CI!=='true'||process.env.SKO_TRADE_DOCUMENT_REAL_AUTH_HOOK!=='contract-v1')throw Error('Dedicated isolated Auth context required');
 context=value;
}
export function tradeDocumentAuthContext(){if(!context)throw Error('Auth fixture context unavailable');return context;}
