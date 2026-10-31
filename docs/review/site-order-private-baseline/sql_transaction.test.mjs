import {test} from 'node:test';
import assert from 'node:assert/strict';
import {transactionBody} from './sql_transaction.mjs';
test('keeps transaction words inside function bodies and strings',()=>{
 const body=transactionBody("-- review\nbegin;create function f() returns text language sql as $$select 'commit;rollback;'$$;select 'begin;';commit;");
 assert.match(body,/commit;rollback/);
});
test('rejects inner transaction escape',()=>{
 for(const word of ['commit','rollback','begin','savepoint x','release x'])assert.throws(()=>transactionBody(`begin;select 1;${word};commit;`),/unexpected_inner_transaction/);
});
test('requires one exact outer transaction',()=>{
 for(const sql of ['select 1;','begin;select 1;','begin;commit;select 1;','start transaction;select 1;commit;'])assert.throws(()=>transactionBody(sql),/exact_outer_transaction_required/);
});
test('nested comments cannot expose transaction words',()=>{
 assert.match(transactionBody('begin;/* commit; /* rollback; */ */ select 1;commit;'),/select 1/);
});
test('rejects unterminated dollar body or comment',()=>{
 assert.throws(()=>transactionBody('begin;select $$bad;commit;'),/unterminated_dollar_body/);
 assert.throws(()=>transactionBody('begin;/* bad'),/unterminated_comment/);
});
