// stdin is a private subprocess pipe; credentials never occur in argv/env/logs.
import fs from 'node:fs';
import {executeRequest} from './production_transport_core.mjs';
try {
 if(process.argv.length!==2) throw Error('arguments_refused');
 const bytes=fs.readFileSync(0);
 if(!bytes.length||bytes.length>33558528) throw Error('input_refused');
 const request=JSON.parse(bytes.toString('utf8'));
 const pg=await import('../fixture_dependencies/node_modules/pg/lib/index.js');
 const result=await executeRequest(request,pg.Client??pg.default?.Client);
 process.stdout.write(JSON.stringify(result));
} catch {
 // Never emit driver/server messages, SQL, request payloads or credentials.
 process.stderr.write('expense_transport_failed_or_commit_unknown\n');process.exitCode=3;
}
