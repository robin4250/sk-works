import {createWorkerHandler} from './handler.mjs';
import {createDeletionServiceClient} from '../account-deletion/service_client.mjs';
import {createConfiguredDeletionWorker} from '../account-deletion/configured_worker.mjs';
const env=(key:string)=>Deno.env.get(key)??'';
// Change only after the dedicated real lifecycle acceptance, not unit tests.
const lifecycleReleaseVerified=false;
Deno.serve(createWorkerHandler({serviceKey:env('SUPABASE_SERVICE_ROLE_KEY'),
 enabled:()=>lifecycleReleaseVerified&&env('ACCOUNT_DELETION_WORKER_ENABLED')==='true',
 createRun:()=>createConfiguredDeletionWorker({env,client:createDeletionServiceClient({origin:env('SUPABASE_URL'),serviceKey:env('SUPABASE_SERVICE_ROLE_KEY')})}),
}));
