// Top-level SQL scanner. Dollar bodies, strings and comments never become TX tokens.
export function statements(sql){
 const out=[];let start=0,i=0,tokens=[];
 const push=end=>{if(tokens.length)out.push({text:sql.slice(start,end),tokens});start=end;tokens=[];};
 while(i<sql.length){
  if(sql.startsWith('--',i)){i=sql.indexOf('\n',i+2);if(i<0)i=sql.length;continue;}
  if(sql.startsWith('/*',i)){let depth=1;i+=2;while(i<sql.length&&depth){if(sql.startsWith('/*',i)){depth++;i+=2;}else if(sql.startsWith('*/',i)){depth--;i+=2;}else i++;}if(depth)throw Error('unterminated_comment');continue;}
  if(sql[i]==="'"||sql[i]==='"'){const quote=sql[i++];while(i<sql.length){if(sql[i]===quote){i++;if(sql[i]===quote){i++;continue;}break;}if(sql[i]==='\\'&&quote==="'")i+=2;else i++;}continue;}
  const dollar=sql.slice(i).match(/^\$(?:[A-Za-z_][A-Za-z_0-9]*)?\$/)?.[0];
  if(dollar){const end=sql.indexOf(dollar,i+dollar.length);if(end<0)throw Error('unterminated_dollar_body');tokens.push('<body>');i=end+dollar.length;continue;}
  if(sql[i]===';'){i++;push(i);continue;}
  const word=sql.slice(i).match(/^[A-Za-z_][A-Za-z_0-9]*/)?.[0];if(word){tokens.push(word.toLowerCase());i+=word.length;}else i++;
 }
 push(sql.length);return out;
}
export function transactionBody(sql){
 const all=statements(sql),is=(s,word)=>s.tokens.length===1&&s.tokens[0]===word;
 if(all.length<2||!is(all[0],'begin')||!is(all.at(-1),'commit'))throw Error('exact_outer_transaction_required');
 const body=all.slice(1,-1);
 if(body.some(s=>['begin','commit','rollback','savepoint','release'].includes(s.tokens[0])))throw Error('unexpected_inner_transaction');
 return body.map(s=>s.text).join('\n');
}
