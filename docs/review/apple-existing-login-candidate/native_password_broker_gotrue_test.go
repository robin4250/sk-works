package api

import (
 "context"
 "crypto/sha256"
 "encoding/base64"
 "encoding/json"
 "fmt"
 "net/http"
 "net/http/httptest"
 "os"
 "os/exec"
 "strings"
 "testing"
 "time"
 "github.com/coreos/go-oidc/v3/oidc"
 "github.com/golang-jwt/jwt/v5"
 "github.com/stretchr/testify/require"
 "golang.org/x/crypto/bcrypt"
 "github.com/supabase/auth/internal/api/provider"
 "github.com/supabase/auth/internal/models"
)

// Official Auth HTTP + exact private enrollment SQL + Node broker integration.
// Provider credential, user/company records and network bridge are synthetic.
// No production endpoint, actual Apple account or managed schema is exercised.
func TestSKOApplePasswordSuccessorBroker(t *testing.T){
 url:=os.Getenv("SKO_APPLE_LIFECYCLE_ADMIN_URL")
 require.Equal(t,"postgresql://postgres:root@127.0.0.1:5432/postgres",url)
 root:=func(q string,args ...interface{})string{for _,arg:=range args{q=strings.Replace(q,"?","'"+strings.ReplaceAll(fmt.Sprint(arg),"'","''")+"'",1)};out,e:=exec.Command("psql",url,"-qAt","-v","ON_ERROR_STOP=1","-c",q).CombinedOutput();require.NoError(t,e,string(out));return strings.TrimSpace(string(out))}
 api,config,err:=setupAPIForTest();require.NoError(t,err);defer api.db.Close()
 models.TruncateAll(api.db)
 originalJWT:=root("select pg_get_functiondef('auth.jwt()'::regprocedure)")
 defer func(){root(originalJWT)}()
 root(`do $$declare r text;begin foreach r in array array['anon','authenticated','service_role']loop if not exists(select 1 from pg_roles where rolname=r)then execute format('create role %I nologin',r);end if;end loop;end$$;
 create schema if not exists private;
 create table public.company_members(user_id uuid,company_id uuid,role text);
 create table private.account_deletion_access_restrictions(user_id uuid primary key);
 create or replace function auth.jwt()returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;`)
 for _,env:=range []string{"SKO_APPLE_POLICY_FILE","SKO_APPLE_ENROLLMENT_FILE","SKO_APPLE_SUCCESSOR_FILE","SKO_APPLE_PASSWORD_SUCCESSOR_FILE"}{b,e:=os.ReadFile(os.Getenv(env));require.NoError(t,e);root(string(b))}
 defer func(){root(`drop schema apple_native_enrollment_private cascade;drop schema apple_owner_policy cascade;
 drop function public.read_apple_native_enrollment_context(uuid,uuid);drop function public.reserve_apple_native_subject(uuid,uuid,text,text,text,text,bigint);drop function public.complete_apple_native_subject(uuid,uuid,uuid,text,text,text);drop function public.hold_apple_native_subject(uuid,uuid,uuid);drop table public.company_members;drop table private.account_deletion_access_restrictions;`)}()
 config.Security.ManualLinkingEnabled=true;config.Sessions.SinglePerUser=true
 config.JWT.Issuer="https://ztktgquxvcxcjxtluspu.supabase.co/auth/v1";config.JWT.Aud="authenticated"
 config.Hook.CustomAccessToken.Enabled=true;config.Hook.CustomAccessToken.URI="pg-functions://postgres/apple_owner_policy/custom_access_token_hook"
 require.NoError(t,config.Hook.CustomAccessToken.PopulateExtensibilityPoint())
 key,client,_:=skoAppleNativeFixture(t);api.oidcCache=provider.NewOIDCProviderCache(time.Minute)
 config.External.Apple.Enabled=true;config.External.Apple.ClientID=[]string{"com.skworks.skWorks"};config.External.Apple.Secret=""
 providerContext:=oidc.ClientContext(context.Background(),client)
 server:=httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter,r *http.Request){
  if !strings.HasPrefix(r.URL.Path,"/auth/v1/"){http.NotFound(w,r);return};r.URL.Path=strings.TrimPrefix(r.URL.Path,"/auth/v1");api.handler.ServeHTTP(w,r.WithContext(providerContext))
 }));defer server.Close()
 for _,mode:=range []string{"success","wrong-password"}{t.Run(mode,func(t *testing.T){
  root("truncate apple_native_enrollment_private.successor_receipts,apple_native_enrollment_private.successor_attempts,apple_native_enrollment_private.password_successor_intents,apple_native_enrollment_private.events,apple_native_enrollment_private.requests,public.company_members,apple_native_enrollment_private.rollout,apple_owner_policy.subject_permits,apple_owner_policy.protected_users,apple_owner_policy.rollout")
  models.TruncateAll(api.db)
  // Official test setup selects MinCost, which Authenticate rehashes. Use
  // the ordinary accepted cost so this success case tests an unchanged credential.
  // The application snapshot guard remains strict for real credential changes.
  passwordHash,e:=bcrypt.GenerateFromPassword([]byte("fixture-primary-password"),bcrypt.DefaultCost);require.NoError(t,e)
  owner,e:=models.NewUserWithPasswordHash("","existing-google@example.test",string(passwordHash),config.JWT.Aud,map[string]interface{}{"full_name":"existing name"});require.NoError(t,e)
  owner.Role="authenticated";owner.AppMetaData=models.JSONMap{"provider":"google","providers":[]string{"google"}};confirmed:=time.Now();owner.EmailConfirmedAt=&confirmed;require.NoError(t,api.db.Create(owner))
  google,e:=models.NewIdentity(owner,"google",map[string]interface{}{"sub":"existing-google-sub","email":"existing-google@example.test","email_verified":true});require.NoError(t,e);require.NoError(t,api.db.Create(google))
  root("insert into public.company_members values(?,'00000000-0000-0000-0000-000000000099','owner')",owner.ID)
  root("insert into apple_owner_policy.rollout values(true,true);insert into apple_native_enrollment_private.rollout values(true,true,true,true);update apple_native_enrollment_private.successor_rollout set enabled=true")
  s,e:=models.NewSession(owner.ID,nil);require.NoError(t,e);require.NoError(t,api.db.Create(s))
  bearer,_,e:=api.generateAccessToken(httptest.NewRequest(http.MethodPost,"/token?grant_type=password",nil),api.db,owner,&s.ID,models.PasswordGrant);require.NoError(t,e)
  snapshot:=func()string{return root("select jsonb_build_object('user',(select jsonb_build_object('id',id,'email',email,'metadata',raw_user_meta_data,'credential_version',encode(sha256(convert_to(encrypted_password,'UTF8')),'hex'))from auth.users where id=?),'google',(select to_jsonb(i)from auth.identities i where id=?),'company',(select jsonb_agg(to_jsonb(c))from public.company_members c where user_id=?))::text",owner.ID,google.ID,owner.ID)}
  before:=snapshot();nonce:=strings.Repeat("n",43);hashed:=sha256.Sum256([]byte(nonce));now:=time.Now().Unix()
  claims:=jwt.MapClaims{"iss":"https://appleid.apple.com","aud":"com.skworks.skWorks","sub":"verified-native-subject","iat":now,"exp":now+600,"nonce":fmt.Sprintf("%x",hashed),"email":"private-relay@example.test","email_verified":true}
  token:=jwt.NewWithClaims(jwt.SigningMethodRS256,claims);token.Header["kid"]="sko-synthetic";signed,e:=token.SignedString(key);require.NoError(t,e)
  password:="fixture-primary-password";if mode=="wrong-password"{password="incorrect-fixture-password"}
  input,e:=json.Marshal(map[string]interface{}{"fixtureURL":server.URL+"/","actor":owner.ID.String(),"originalSID":s.ID.String(),"originalBearer":bearer,"password":password,"idToken":signed,"rawNonce":nonce,"expected":mode,"jwk":map[string]interface{}{"kid":"sko-synthetic","kty":"RSA","alg":"RS256","use":"sig","n":base64.RawURLEncoding.EncodeToString(key.N.Bytes()),"e":"AQAB"}});require.NoError(t,e)
  ctx,cancel:=context.WithTimeout(context.Background(),60*time.Second);defer cancel()
  cmd:=exec.CommandContext(ctx,"node",os.Getenv("SKO_APPLE_PASSWORD_BROKER_RUNNER"));cmd.Stdin=strings.NewReader(string(input));out,e:=cmd.CombinedOutput();require.NoError(t,e,string(out))
  var receipt map[string]interface{};require.NoError(t,json.Unmarshal(out,&receipt));require.Equal(t,true,receipt["verified"])
  require.Equal(t,before,snapshot(),"UID/profile/password/Google/company preserved")
  if mode=="success"{require.Equal(t,"1",root("select count(*) from auth.identities where user_id=? and provider='apple'",owner.ID))}else{require.Equal(t,"0",root("select count(*) from auth.identities where provider='apple'"))}
 })}
}
