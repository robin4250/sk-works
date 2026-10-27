package api

import (
 "context"
 "crypto/rand"
 "crypto/rsa"
 "crypto/sha256"
 "encoding/base64"
 "encoding/json"
 "fmt"
 "io"
 "net/http"
 "net/http/httptest"
 "os"
 "strings"
 "testing"
 "time"

 "github.com/coreos/go-oidc/v3/oidc"
 "github.com/golang-jwt/jwt/v5"
 "github.com/stretchr/testify/require"
 "github.com/supabase/auth/internal/api/provider"
 "github.com/supabase/auth/internal/models"
 "github.com/supabase/auth/internal/storage"
)

// Real HTTP ID-token API, actual official Auth/PG transaction and trigger.
// Only offline generated provider keys/credentials are used; no external request.
func TestSKOAppleGlobalGoogleProtection(t *testing.T){
 api,config,err:=setupAPIForTest();require.NoError(t,err);defer api.db.Close()
 require.NoError(t,api.db.RawQuery("drop schema if exists apple_google_protection cascade;drop schema if exists apple_owner_policy cascade").Exec())
 base,err:=os.ReadFile(os.Getenv("SKO_APPLE_POLICY_FILE"));require.NoError(t,err)
 guard,err:=os.ReadFile(os.Getenv("SKO_APPLE_GOOGLE_PROTECTION_FILE"));require.NoError(t,err)
 require.NoError(t,api.db.RawQuery(string(base)).Exec());require.NoError(t,api.db.RawQuery(string(guard)).Exec())
 defer func(){require.NoError(t,api.db.RawQuery("drop schema if exists apple_google_protection cascade;drop schema if exists apple_owner_policy cascade").Exec())}()
 require.NoError(t,api.db.RawQuery("create table apple_google_protection.company_snapshot(user_id uuid primary key,company_id uuid not null,role text not null)").Exec())
 config.DisableSignup=false;config.Security.ManualLinkingEnabled=true
 config.Hook.CustomAccessToken.Enabled=true;config.Hook.CustomAccessToken.URI="pg-functions://postgres/apple_owner_policy/custom_access_token_hook"
 require.NoError(t,config.Hook.CustomAccessToken.PopulateExtensibilityPoint())
 config.External.Apple.Enabled=true;config.External.Apple.ClientID=[]string{"com.skworks.skWorks"};config.External.Apple.Secret=""
 config.External.Google.Enabled=true;config.External.Google.ClientID=[]string{"synthetic-google-client"}
 key,err:=rsa.GenerateKey(rand.Reader,2048);require.NoError(t,err)
 client:=&http.Client{Transport:skoAppleOfflineTransport(func(r *http.Request)(*http.Response,error){
  if r.Method!=http.MethodGet||r.URL.Scheme!="https"||(r.URL.Host!="appleid.apple.com"&&r.URL.Host!="accounts.google.com")||r.URL.RawQuery!=""{return nil,fmt.Errorf("fixture rejects external request")}
  issuer:="https://"+r.URL.Host;var v interface{}
  switch r.URL.Path{
  case "/.well-known/openid-configuration":v=map[string]interface{}{"issuer":issuer,"authorization_endpoint":issuer+"/authorize","token_endpoint":issuer+"/token","jwks_uri":issuer+"/sko-global-keys","response_types_supported":[]string{"code"},"subject_types_supported":[]string{"public"},"id_token_signing_alg_values_supported":[]string{"RS256"}}
  case "/sko-global-keys":v=map[string]interface{}{"keys":[]interface{}{map[string]interface{}{"kty":"RSA","kid":"sko-global-synthetic","alg":"RS256","use":"sig","n":base64.RawURLEncoding.EncodeToString(key.N.Bytes()),"e":"AQAB"}}}
  default:return nil,fmt.Errorf("fixture rejects path")
  }
  b,e:=json.Marshal(v);if e!=nil{return nil,e};return &http.Response{StatusCode:200,Header:http.Header{"Content-Type":[]string{"application/json"}},Body:io.NopCloser(strings.NewReader(string(b))),Request:r},nil
 })}
 ctx:=oidc.ClientContext(context.Background(),client)
 type tokenResult struct{AccessToken string `json:"access_token"`;RefreshToken string `json:"refresh_token"`;User struct{ID string `json:"id"`} `json:"user"`}
 for _,name:=range []string{"existing Google unknown Apple direct native","new Google registration protected immediately","returning Google and primary password remain usable","same-UID enrolled native Apple admitted","PKCE identity-stage commit is now rejected","reverse Google automatic merge denied","user metadata cannot remove protection","token-hook flag drift retains write guard","deleted Google subject cannot become new UID","official soft deletion keeps old subject ownership","lost Google response retry keeps original UID","unlink retains protection and Google can resume same UID","Apple subject cannot transfer between existing users"}{t.Run(name,func(t *testing.T){
  models.TruncateAll(api.db)
  require.NoError(t,api.db.RawQuery("truncate apple_owner_policy.subject_permits,apple_owner_policy.protected_users,apple_owner_policy.rollout,apple_google_protection.rollout,apple_google_protection.google_subject_owners,apple_google_protection.company_snapshot").Exec())
  createUser:=func(email,googleSub string)*models.User{
   u,e:=models.NewUser("",email,"fixture-primary-password",config.JWT.Aud,map[string]interface{}{"full_name":"existing name","custom_field":"preserved"});require.NoError(t,e)
   u.AppMetaData=map[string]interface{}{"provider":"google","providers":[]string{"google"}}
   confirmed:=time.Now();u.EmailConfirmedAt=&confirmed;require.NoError(t,api.db.Create(u))
   if googleSub!=""{i,e:=models.NewIdentity(u,"google",map[string]interface{}{"sub":googleSub,"email":email,"email_verified":true});require.NoError(t,e);require.NoError(t,api.db.Create(i))}
   require.NoError(t,api.db.RawQuery("insert into apple_google_protection.company_snapshot values(?,'00000000-0000-0000-0000-000000000099','owner')",u.ID).Exec());return u
  }
  call:=func(path string,data interface{},bearer string)*httptest.ResponseRecorder{
   bytes,e:=json.Marshal(data);require.NoError(t,e);r:=httptest.NewRequest(http.MethodPost,"http://localhost"+path,strings.NewReader(string(bytes))).WithContext(ctx);r.Header.Set("Content-Type","application/json");if bearer!=""{r.Header.Set("Authorization","Bearer "+bearer)};w:=httptest.NewRecorder();api.handler.ServeHTTP(w,r);return w
  }
  idToken:=func(kind,subject,email,bearer string,link bool)*httptest.ResponseRecorder{
   issuer:="https://appleid.apple.com";aud:="com.skworks.skWorks";if kind=="google"{issuer="https://accounts.google.com";aud="synthetic-google-client"}
   rawNonce:=strings.Repeat("n",43);hash:=sha256.Sum256([]byte(rawNonce));now:=time.Now().Unix()
   claims:=jwt.MapClaims{"iss":issuer,"sub":subject,"aud":aud,"iat":now,"exp":now+600,"nonce":fmt.Sprintf("%x",hash),"email":email,"email_verified":true,"name":"existing name"}
   token:=jwt.NewWithClaims(jwt.SigningMethodRS256,claims);token.Header["kid"]="sko-global-synthetic";signed,e:=token.SignedString(key);require.NoError(t,e)
   return call("/token?grant_type=id_token",map[string]interface{}{"provider":kind,"id_token":signed,"nonce":rawNonce,"link_identity":link},bearer)
  }
  enable:=func(){var result string;require.NoError(t,api.db.RawQuery("select apple_google_protection.enable_reviewed()::text").First(&result))}
  counts:=func()[3]int{var x [3]int;for i,table:=range []string{"users","identities","sessions"}{require.NoError(t,api.db.RawQuery("select count(*)from auth."+table).First(&x[i]))};return x}
  denied:=func(w *httptest.ResponseRecorder,before [3]int){require.NotEqual(t,http.StatusOK,w.Code);require.Equal(t,before,counts(),"failed direct flow must roll back user, identity and session together")}
  result:=func(w *httptest.ResponseRecorder)tokenResult{require.Equal(t,http.StatusOK,w.Code);var r tokenResult;require.NoError(t,json.Unmarshal(w.Body.Bytes(),&r));require.NotEmpty(t,r.AccessToken);return r}
  snapshot:=func(u *models.User)string{var v string;require.NoError(t,api.db.RawQuery("select jsonb_build_object('id',id,'email',email,'custom',raw_user_meta_data->>'custom_field','name',raw_user_meta_data->>'full_name','company',(select to_jsonb(c)from apple_google_protection.company_snapshot c where c.user_id=u.id),'google',(select coalesce(jsonb_agg(jsonb_build_object('id',i.id,'subject',i.provider_id)order by i.id),'[]')from auth.identities i where i.user_id=u.id and i.provider='google'))::text from auth.users u where id=?",u.ID).First(&v));return v}
  if name=="new Google registration protected immediately"{
   enable();first:=result(idToken("google","fresh-google","fresh@example.test","",false));var protected string
   require.NoError(t,api.db.RawQuery("select user_id::text from apple_google_protection.google_subject_owners where provider_id='fresh-google'").First(&protected));require.Equal(t,first.User.ID,protected)
   before:=counts();denied(idToken("apple","unknown-apple","fresh@example.test","",false),before);return
  }
  if name=="reverse Google automatic merge denied"{
   owner:=createUser("apple-first@example.test","");require.NoError(t,api.db.RawQuery("update auth.users set raw_app_meta_data='{\"provider\":\"apple\",\"providers\":[\"apple\"]}'::jsonb where id=?",owner.ID).Exec());i,e:=models.NewIdentity(owner,"apple",map[string]interface{}{"sub":"apple-first","email":string(owner.Email),"email_verified":true});require.NoError(t,e);require.NoError(t,api.db.Create(i));enable()
   before:=counts();denied(idToken("google","new-google",string(owner.Email),"",false),before);return
  }
  if name=="Apple subject cannot transfer between existing users"{
   owner:=createUser("owner@example.test","owner-google-sub")
   other:=createUser("other@example.test","other-google-sub")
   require.NoError(t,api.db.RawQuery("insert into apple_owner_policy.subject_permits values('foreign-apple-sub',?)",other.ID).Exec())
   identity,e:=models.NewIdentity(other,"apple",map[string]interface{}{"sub":"foreign-apple-sub","email":"other@example.test","email_verified":true});require.NoError(t,e);require.NoError(t,api.db.Create(identity))
   enable();beforeOwner,beforeOther:=snapshot(owner),snapshot(other)
   ownerSession:=result(idToken("google","owner-google-sub",string(owner.Email),"",false))
   otherSession:=result(idToken("google","other-google-sub",string(other.Email),"",false))
   require.Equal(t,owner.ID.String(),ownerSession.User.ID);require.Equal(t,other.ID.String(),otherSession.User.ID)
   before:=counts();denied(idToken("apple","foreign-apple-sub",string(owner.Email),ownerSession.AccessToken,true),before)
   require.Equal(t,beforeOwner,snapshot(owner));require.Equal(t,beforeOther,snapshot(other))
   var bound string;require.NoError(t,api.db.RawQuery("select user_id::text from auth.identities where provider='apple' and provider_id='foreign-apple-sub'").First(&bound));require.Equal(t,other.ID.String(),bound)
   ownerAgain:=result(idToken("google","owner-google-sub",string(owner.Email),"",false));otherAgain:=result(idToken("google","other-google-sub",string(other.Email),"",false))
   require.Equal(t,owner.ID.String(),ownerAgain.User.ID);require.Equal(t,other.ID.String(),otherAgain.User.ID);return
  }
  owner:=createUser("existing-google@example.test","existing-google-sub");enable();originalSnapshot:=snapshot(owner)
  if name=="token-hook flag drift retains write guard"{require.NoError(t,api.db.RawQuery("update apple_owner_policy.rollout set enabled=false").Exec())}
  if name=="PKCE identity-stage commit is now rejected"{
   before:=counts();data:=&provider.UserProvidedData{Metadata:&provider.Claims{Subject:"unregistered-pkce",Email:string(owner.Email),EmailVerified:true},Emails:[]provider.Email{{Email:string(owner.Email),Primary:true,Verified:true}}}
   req:=httptest.NewRequest(http.MethodGet,"/callback?code=synthetic-pkce",nil)
   err:=api.db.Transaction(func(tx *storage.Connection)error{_,_,e:=api.createAccountFromExternalIdentity(tx,req,data,"apple",false);return e})
   require.Error(t,err,"write-stage guard must reject before the earlier PKCE identity transaction can commit");require.Equal(t,before,counts());require.Equal(t,originalSnapshot,snapshot(owner));return
  }
  if name=="deleted Google subject cannot become new UID"{
   require.NoError(t,api.db.RawQuery("insert into apple_owner_policy.subject_permits values('registered-old-subject',?)",owner.ID).Exec())
   require.NoError(t,api.db.RawQuery("delete from auth.users where id=?",owner.ID).Exec());before:=counts()
   denied(idToken("google","existing-google-sub",string(owner.Email),"",false),before);denied(idToken("apple","registered-old-subject",string(owner.Email),"",false),before)
   var old string;require.NoError(t,api.db.RawQuery("select user_id::text from apple_google_protection.google_subject_owners where provider_id='existing-google-sub'").First(&old));require.Equal(t,owner.ID.String(),old);return
  }
  original:=result(idToken("google","existing-google-sub",string(owner.Email),"",false));require.Equal(t,owner.ID.String(),original.User.ID)
  if name=="official soft deletion keeps old subject ownership"{
   require.NoError(t,api.db.RawQuery("insert into apple_owner_policy.subject_permits values('registered-old-subject',?)",owner.ID).Exec())
   i,e:=models.NewIdentity(owner,"apple",map[string]interface{}{"sub":"registered-old-subject","email":string(owner.Email),"email_verified":true});require.NoError(t,e);require.NoError(t,api.db.Create(i))
   realEmail:=string(owner.Email)
   require.NoError(t,api.db.Transaction(func(tx *storage.Connection)error{if e:=owner.SoftDeleteUser(tx);e!=nil{return e};return owner.SoftDeleteUserIdentities(tx)}))
   before:=counts();denied(idToken("google","existing-google-sub",realEmail,"",false),before);denied(idToken("apple","registered-old-subject",realEmail,"",false),before)
   var old string;require.NoError(t,api.db.RawQuery("select user_id::text from apple_google_protection.google_subject_owners where provider_id='existing-google-sub'").First(&old));require.Equal(t,owner.ID.String(),old)
   require.NoError(t,api.db.RawQuery("delete from auth.users where id=?",owner.ID).Exec());before=counts()
   denied(idToken("google","existing-google-sub",realEmail,"",false),before);return
  }
  if name=="lost Google response retry keeps original UID"{
   // The earlier successful response could have been lost before adoption.
   // A credential retry may issue a session but must not create another person.
   retry:=result(idToken("google","existing-google-sub",string(owner.Email),"",false));require.Equal(t,original.User.ID,retry.User.ID)
   var n int;require.NoError(t,api.db.RawQuery("select count(*)from apple_google_protection.google_subject_owners where provider_id='existing-google-sub'").First(&n));require.Equal(t,1,n)
  }
  if name=="returning Google and primary password remain usable"{
   password:=result(call("/token?grant_type=password",map[string]interface{}{"email":string(owner.Email),"password":"fixture-primary-password"},""));require.Equal(t,owner.ID.String(),password.User.ID)
  }else if name=="same-UID enrolled native Apple admitted"{
   require.NoError(t,api.db.RawQuery("insert into apple_owner_policy.subject_permits values('verified-native-subject',?)",owner.ID).Exec())
   linked:=result(idToken("apple","verified-native-subject","private-relay@example.test",original.AccessToken,true));require.Equal(t,owner.ID.String(),linked.User.ID)
  }else if name=="unlink retains protection and Google can resume same UID"{
   require.NoError(t,api.db.RawQuery("delete from auth.identities where user_id=? and provider='google'",owner.ID).Exec())
   before:=counts();denied(idToken("apple","unregistered-after-unlink",string(owner.Email),"",false),before)
   resumed:=result(idToken("google","existing-google-sub",string(owner.Email),"",false));require.Equal(t,owner.ID.String(),resumed.User.ID)
  }else if name!="lost Google response retry keeps original UID"{
   if name=="user metadata cannot remove protection"{
    bytes,_:=json.Marshal(map[string]interface{}{"data":map[string]interface{}{"protected":false,"provider":"none","providers":[]string{}}})
    update:=httptest.NewRequest(http.MethodPut,"http://localhost/user",strings.NewReader(string(bytes)));update.Header.Set("Content-Type","application/json");update.Header.Set("Authorization","Bearer "+original.AccessToken);w:=httptest.NewRecorder();api.handler.ServeHTTP(w,update);require.Equal(t,http.StatusOK,w.Code)
   }
   before:=counts();denied(idToken("apple","unknown-apple",string(owner.Email),"",false),before)
  }
  if name=="unlink retains protection and Google can resume same UID"{
   // Explicit unlink removed the identity row; a new row ID is legitimate on
   // relink. The person UID, provider subject, profile and company must persist.
   var before,after map[string]interface{};require.NoError(t,json.Unmarshal([]byte(originalSnapshot),&before));require.NoError(t,json.Unmarshal([]byte(snapshot(owner)),&after))
   for _,state:=range []map[string]interface{}{before,after}{for _,value:=range state["google"].([]interface{}){delete(value.(map[string]interface{}),"id")}}
   require.Equal(t,before,after)
  }else{require.Equal(t,originalSnapshot,snapshot(owner),"existing UID, email, profile fields, Google identity and company preserved")}
  // Beyond getUser: a rejected linking attempt must not invalidate the original
  // refresh credential used by the existing app/Face ID path. No Face ID hardware
  // or hosted single-session claim is made by this fixture.
  refreshed:=result(call("/token?grant_type=refresh_token",map[string]interface{}{"refresh_token":original.RefreshToken},""));require.Equal(t,owner.ID.String(),refreshed.User.ID)
 })}
}
