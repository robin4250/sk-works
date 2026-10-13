import {createDirectoryRefreshHandler} from './handler.mjs';
Deno.serve(createDirectoryRefreshHandler({env:(name:string)=>Deno.env.get(name)}));
