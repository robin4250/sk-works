import {createLineChatDispatchHandler} from './handler.mjs';
Deno.serve(createLineChatDispatchHandler({env:(name:string)=>Deno.env.get(name)}));
