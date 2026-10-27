// Disposable CI PostgreSQL fixture only. Reject every other URL before opening
// a socket; this module must never become an application database adapter.
import {randomBytes} from 'node:crypto';
const fixed='postgresql://postgres:fixture-only-password@127.0.0.1:5432/sko_apple_enrollment_fixture';
export class NativeRuntime{
 constructor(){
  if(process.env.SKO_APPLE_ENROLLMENT_NATIVE_URL!==fixed)throw Error('isolated_native_fixture_only');
  this.name='apple_enrollment_case_'+randomBytes(12).toString('hex');this.peers=[];
  this.ready=this.open();
 }
 async open(){
  const {default:pg}=await import(process.env.SKO_APPLE_ENROLLMENT_NATIVE_DRIVER);
  this.Client=pg.Client;this.admin=new pg.Client({connectionString:fixed});await this.admin.connect();
  await this.admin.query('create database "'+this.name+'"');
  const url=new URL(fixed);url.pathname='/'+this.name;this.url=url.toString();
  this.client=new pg.Client({connectionString:this.url});await this.client.connect();
 }
 async query(sql,params=[]){await this.ready;return this.client.query(sql,params);}
 async exec(sql){await this.ready;return this.client.query(sql);}
 async peer(){await this.ready;const c=new this.Client({connectionString:this.url});await c.connect();this.peers.push(c);return c;}
 async close(){
  try{await this.ready;for(const c of this.peers)await c.end();if(this.client)await this.client.end();
   await this.admin.query('drop database if exists "'+this.name+'" with (force)');
  }finally{if(this.admin)await this.admin.end();}
 }
}
