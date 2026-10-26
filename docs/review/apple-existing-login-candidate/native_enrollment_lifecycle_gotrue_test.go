package api
import("context";"crypto/sha256";"encoding/json";"fmt";"net/http";"net/http/httptest";"os";"strings";"testing";"time";
"github.com/coreos/go-oidc/v3/oidc";"github.com/golang-jwt/jwt/v5";"github.com/stretchr/testify/require";"github.com/supabase/auth/internal/api/provider";"github.com/supabase/auth/internal/models")
func TestSKOAppleNativeEnrollmentLedgerLifecycle(t *testing.T){
 api,config,err:=setupAPIForTest();require.NoError(t,err);defer api.db.Close()
 require.NoError(t,api.db.RawQuery("drop schema if exists apple_owner_policy cascade").Exec())
 sql,err:=os.ReadFile(os.Getenv("SKO_APPLE_POLICY_FILE"));require.NoError(t,err)
 require.NoError(t,api.db.RawQuery(string(sql)).Exec())
 defer func(){require.NoError(t,api.db.RawQuery("drop schema if exists apple_owner_policy cascade").Exec())}()
 require.NoError(t,api.db.RawQuery("create table public.sko_apple_company_snapshot(user_id uuid primary key,company_id uuid not null,role text not null)").Exec())
 defer func(){require.NoError(t,api.db.RawQuery("drop table public.sko_apple_company_snapshot").Exec())}()

 require.NoError(t,api.db.RawQuery(`do $$declare r text;begin foreach r in array array['anon','authenticated','service_role']loop if not exists(select 1 from pg_roles where rolname=r)then execute format('create role %I nologin',r);end if;end loop;end$$;
 create schema if not exists private;
 create table public.company_members(user_id uuid,company_id uuid,role text);
 create table private.account_deletion_access_restrictions(user_id uuid primary key);
 create function auth.jwt()returns jsonb language sql stable as $$select '{"role":"service_role"}'::jsonb$$;`).Exec())
 ledgerSQL,err:=os.ReadFile(os.Getenv("SKO_APPLE_ENROLLMENT_FILE"));require.NoError(t,err)
 require.NoError(t,api.db.RawQuery(string(ledgerSQL)).Exec())
 defer func(){require.NoError(t,api.db.RawQuery(`drop schema apple_native_enrollment_private cascade;drop function public.read_apple_native_enrollment_context(uuid,uuid);drop function public.reserve_apple_native_subject(uuid,uuid,text,text,text,text,bigint);drop function public.complete_apple_native_subject(uuid,uuid,uuid,text,text,text);drop function public.hold_apple_native_subject(uuid,uuid,uuid);drop function auth.jwt();drop table public.company_members;drop table private.account_deletion_access_restrictions;`).Exec())}()
 config.Security.ManualLinkingEnabled=true
 config.Hook.CustomAccessToken.Enabled=true
 config.Hook.CustomAccessToken.URI="pg-functions://postgres/apple_owner_policy/custom_access_token_hook"
 require.NoError(t,config.Hook.CustomAccessToken.PopulateExtensibilityPoint())
 key,client,_:=skoAppleNativeFixture(t)
 api.oidcCache=provider.NewOIDCProviderCache(time.Minute)
 config.External.Apple.Enabled=true;config.External.Apple.ClientID=[]string{"com.skworks.skWorks"};config.External.Apple.Secret=""
 ctx:=oidc.ClientContext(context.Background(),client)
 for _,tc:=range []struct{name string;permit,wrongNonce,wrongBearer bool}{
  {name:"permitted native link preserves original Google session",permit:true},
  {name:"missing subject permit rolls back native identity and session"},
  {name:"wrong native nonce never writes an identity",permit:true,wrongNonce:true},
  {name:"wrong original bearer never reaches native linking",permit:true,wrongBearer:true},
 }{t.Run(tc.name,func(t *testing.T){
  require.NoError(t,api.db.RawQuery("truncate apple_native_enrollment_private.events,apple_native_enrollment_private.requests,apple_native_enrollment_private.rollout,public.company_members").Exec())
  models.TruncateAll(api.db)
  require.NoError(t,api.db.RawQuery("truncate apple_owner_policy.subject_permits,apple_owner_policy.protected_users,apple_owner_policy.rollout,public.sko_apple_company_snapshot").Exec())
  owner,err:=models.NewUser("","existing-google@example.test","fixture-primary-password",config.JWT.Aud,map[string]interface{}{"full_name":"existing name","custom_field":"preserved"});require.NoError(t,err)
  confirmed:=time.Now();owner.EmailConfirmedAt=&confirmed;require.NoError(t,api.db.Create(owner))
  google,err:=models.NewIdentity(owner,"google",map[string]interface{}{"sub":"existing-google-sub","email":"existing-google@example.test","email_verified":true});require.NoError(t,err);require.NoError(t,api.db.Create(google))
  if !tc.permit {require.NoError(t,api.db.RawQuery("insert into apple_owner_policy.protected_users values(?)",owner.ID).Exec())}
  require.NoError(t,api.db.RawQuery("insert into public.company_members values(?,'00000000-0000-0000-0000-000000000099','owner')",owner.ID).Exec())
  require.NoError(t,api.db.RawQuery("insert into apple_native_enrollment_private.rollout values(true,true,true,true)").Exec())
  require.NoError(t,api.db.RawQuery("insert into apple_owner_policy.rollout values(true,true)").Exec())

  require.NoError(t,api.db.RawQuery("insert into public.sko_apple_company_snapshot values(?,'00000000-0000-0000-0000-000000000099','owner')",owner.ID).Exec())
  originalSession,err:=models.NewSession(owner.ID,nil);require.NoError(t,err);require.NoError(t,api.db.Create(originalSession))
  originalRequest:=httptest.NewRequest(http.MethodPost,"/token?grant_type=password",nil)
  originalToken,_,err:=api.generateAccessToken(originalRequest,api.db,owner,&originalSession.ID,models.PasswordGrant);require.NoError(t,err)
  snapshot:=func()string{var state string;require.NoError(t,api.db.RawQuery("select jsonb_build_object('user',(select jsonb_build_object('id',id,'email',email,'metadata',raw_user_meta_data)from auth.users where id=?),'google',(select to_jsonb(i)from auth.identities i where id=?),'company',(select to_jsonb(c)from public.sko_apple_company_snapshot c where user_id=?))::text",owner.ID,google.ID,owner.ID).First(&state));return state}
  before:=snapshot()
  count:=func(table string)int{var n int;require.NoError(t,api.db.RawQuery("select count(*)from auth."+table).First(&n));return n}
  users,identities,sessions:=count("users"),count("identities"),count("sessions")
  rawNonce:=strings.Repeat("n",43);hash:=sha256.Sum256([]byte(rawNonce));now:=time.Now().Unix()
  claims:=jwt.MapClaims{"iss":"https://appleid.apple.com","aud":"com.skworks.skWorks","sub":"verified-native-subject","iat":now,"exp":now+600,"nonce":fmt.Sprintf("%x",hash),"email":"private-relay@example.test","email_verified":true}
  token:=jwt.NewWithClaims(jwt.SigningMethodRS256,claims);token.Header["kid"]="sko-synthetic";signed,err:=token.SignedString(key);require.NoError(t,err)

  var requestID,snapshotHash,tokenHash string
  if tc.permit {
   var rawContext string
   require.NoError(t,api.db.RawQuery("select public.read_apple_native_enrollment_context(?,?)::text",owner.ID,originalSession.ID).First(&rawContext))
   var c map[string]interface{};require.NoError(t,json.Unmarshal([]byte(rawContext),&c));delete(c,"account_allowed");delete(c,"primary_password_configured")
   raw,err:=json.Marshal(c);require.NoError(t,err);h:=sha256.Sum256(raw);snapshotHash=fmt.Sprintf("%x",h);th:=sha256.Sum256([]byte(signed));tokenHash=fmt.Sprintf("%x",th)
   var reserved string
   require.NoError(t,api.db.RawQuery("select public.reserve_apple_native_subject(?,?,?,?,?,?,?)::text",owner.ID,originalSession.ID,"verified-native-subject",tokenHash,snapshotHash,string(raw),now).First(&reserved))
   var rr map[string]interface{};require.NoError(t,json.Unmarshal([]byte(reserved),&rr));requestID=rr["request_id"].(string);require.Equal(t,"reserved",rr["status"])
   var permit string;require.NoError(t,api.db.RawQuery("select expected_user_id::text from apple_owner_policy.subject_permits where apple_subject='verified-native-subject'").First(&permit));require.Equal(t,owner.ID.String(),permit)
  }
  sentNonce:=rawNonce;if tc.wrongNonce{sentNonce="different-raw-nonce"}
  body,err:=json.Marshal(map[string]interface{}{"provider":"apple","id_token":signed,"nonce":sentNonce,"link_identity":true});require.NoError(t,err)
  req:=httptest.NewRequest(http.MethodPost,"http://localhost/token?grant_type=id_token",strings.NewReader(string(body))).WithContext(ctx)
  req.Header.Set("Content-Type","application/json");authorization:=originalToken;if tc.wrongBearer{authorization="invalid-fixture-bearer"};req.Header.Set("Authorization","Bearer "+authorization)
  response:=httptest.NewRecorder();api.handler.ServeHTTP(response,req)
  if tc.permit&&!tc.wrongNonce&&!tc.wrongBearer{
   require.Equal(t,http.StatusOK,response.Code)
   var result struct{AccessToken string `json:"access_token"`;User struct{ID string `json:"id"`} `json:"user"`};require.NoError(t,json.Unmarshal(response.Body.Bytes(),&result));require.Equal(t,owner.ID.String(),result.User.ID);require.NotEmpty(t,result.AccessToken)
   require.Equal(t,users,count("users"));require.Equal(t,identities+1,count("identities"));require.Equal(t,sessions+1,count("sessions"))
   current:=httptest.NewRequest(http.MethodGet,"http://localhost/user",nil);current.Header.Set("Authorization","Bearer "+result.AccessToken);checked:=httptest.NewRecorder();api.handler.ServeHTTP(checked,current);require.Equal(t,http.StatusOK,checked.Code)
   logout:=httptest.NewRequest(http.MethodPost,"http://localhost/logout?scope=local",nil);logout.Header.Set("Authorization","Bearer "+result.AccessToken);closed:=httptest.NewRecorder();api.handler.ServeHTTP(closed,logout);require.Equal(t,http.StatusNoContent,closed.Code)
   require.Equal(t,sessions,count("sessions"),"only newly issued native session is removed")
   var completed string
   require.NoError(t,api.db.RawQuery("select public.complete_apple_native_subject(?,?,?,?,?,?)::text",requestID,owner.ID,originalSession.ID,"verified-native-subject",tokenHash,snapshotHash).First(&completed))
   var rr map[string]interface{};require.NoError(t,json.Unmarshal([]byte(completed),&rr));require.Equal(t,true,rr["linked"])
   var status string;require.NoError(t,api.db.RawQuery("select status from apple_native_enrollment_private.requests where request_id=?",requestID).First(&status));require.Equal(t,"completed",status)

  }else{
   require.NotEqual(t,http.StatusOK,response.Code)
   if tc.permit {var held string;require.NoError(t,api.db.RawQuery("select public.hold_apple_native_subject(?,?,?)::text",requestID,owner.ID,originalSession.ID).First(&held));var status string;require.NoError(t,api.db.RawQuery("select status from apple_native_enrollment_private.requests where request_id=?",requestID).First(&status));require.Equal(t,"held",status)}
   require.Equal(t,users,count("users"));require.Equal(t,identities,count("identities"));require.Equal(t,sessions,count("sessions"))
  }
  require.Equal(t,before,snapshot(),"original UID/email/profile/Google identity/company preserved")
  original:=httptest.NewRequest(http.MethodGet,"http://localhost/user",nil);original.Header.Set("Authorization","Bearer "+originalToken);stillLive:=httptest.NewRecorder();api.handler.ServeHTTP(stillLive,original);require.Equal(t,http.StatusOK,stillLive.Code,"original session remains usable")
 })}
}
