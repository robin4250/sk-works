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
 "sync/atomic"
 "testing"
 "time"

 "github.com/coreos/go-oidc/v3/oidc"
 "github.com/golang-jwt/jwt/v5"
 "github.com/stretchr/testify/require"
 "github.com/supabase/auth/internal/api/provider"
 "github.com/supabase/auth/internal/conf"
 "github.com/supabase/auth/internal/models"
)

type skoAppleOfflineTransport func(*http.Request)(*http.Response,error)
func (f skoAppleOfflineTransport) RoundTrip(r *http.Request)(*http.Response,error){return f(r)}

func skoAppleNativeFixture(t *testing.T)(*rsa.PrivateKey,*http.Client,*atomic.Int32){
 t.Helper()
 key,err:=rsa.GenerateKey(rand.Reader,2048);require.NoError(t,err)
 const issuer="https://appleid.apple.com"
 calls:=&atomic.Int32{}
 client:=&http.Client{Transport:skoAppleOfflineTransport(func(r *http.Request)(*http.Response,error){
  calls.Add(1)
  if r.Method!=http.MethodGet || r.URL.Scheme!="https" || r.URL.Host!="appleid.apple.com" || r.URL.RawQuery!="" {return nil,fmt.Errorf("unreviewed fixture request")}
  var body interface{}
  switch r.URL.Path{
  case "/.well-known/openid-configuration":
   body=map[string]interface{}{"issuer":issuer,"authorization_endpoint":issuer+"/auth/authorize","token_endpoint":issuer+"/auth/token","jwks_uri":issuer+"/sko-fixture-keys","response_types_supported":[]string{"code"},"subject_types_supported":[]string{"public"},"id_token_signing_alg_values_supported":[]string{"RS256"}}
  case "/sko-fixture-keys":
   body=map[string]interface{}{"keys":[]interface{}{map[string]interface{}{"kty":"RSA","kid":"sko-synthetic","alg":"RS256","use":"sig","n":base64.RawURLEncoding.EncodeToString(key.N.Bytes()),"e":"AQAB"}}}
  default:return nil,fmt.Errorf("unreviewed fixture path")
  }
  b,e:=json.Marshal(body);if e!=nil{return nil,e}
  return &http.Response{StatusCode:200,Header:http.Header{"Content-Type":[]string{"application/json"}},Body:io.NopCloser(strings.NewReader(string(b))),Request:r},nil
 })}
 return key,client,calls
}

// Configuration/provider proof only. No account/identity/session write and no
// external connection. This does not prove hosted configuration or safe enrollment.
func TestSKOAppleNativeOnlyConfigurationBoundary(t *testing.T){
 key,client,calls:=skoAppleNativeFixture(t)
 const bundle="com.skworks.skWorks"
 const issuer="https://appleid.apple.com"
 ctx:=oidc.ClientContext(context.Background(),client)
 cfg:=&conf.GlobalConfiguration{}
 cfg.External.Apple.Enabled=true
 cfg.External.Apple.ClientID=[]string{bundle}
 cfg.External.Apple.RedirectURI="https://callback.example.invalid/auth/v1/callback"
 cfg.External.Apple.Secret=""
 cache:=provider.NewOIDCProviderCache(time.Minute)
 before:=calls.Load()
 _,err:=provider.NewAppleProvider(ctx,cfg.External.Apple,cache)
 require.ErrorContains(t,err,"missing OAuth secret")
 require.Equal(t,before,calls.Load(),"OAuth is rejected before discovery or identity work")

 now:=time.Now().Unix()
 claims:=jwt.MapClaims{"iss":issuer,"sub":"synthetic-existing-apple","aud":bundle,"iat":now,"exp":now+600,"email":"synthetic@example.invalid","email_verified":true,"nonce":"synthetic-provider-nonce"}
 token:=jwt.NewWithClaims(jwt.SigningMethodRS256,claims);token.Header["kid"]="sko-synthetic"
 signed,err:=token.SignedString(key);require.NoError(t,err)
 params:=&IdTokenGrantParams{Provider:"apple",IdToken:signed}
 req:=httptest.NewRequest(http.MethodPost,"https://auth.example.invalid/token?grant_type=id_token",nil)
 discovered,skipNonce,kind,audiences,_,err:=params.getProvider(ctx,nil,cfg,req,cache)
 require.NoError(t,err);require.NotNil(t,discovered);require.False(t,skipNonce);require.Equal(t,"apple",kind);require.Equal(t,[]string{bundle},audiences)
 verified,data,err:=provider.ParseIDToken(ctx,discovered,&oidc.Config{ClientID:bundle},signed,provider.ParseIDTokenOptions{})
 require.NoError(t,err);require.Equal(t,"synthetic-existing-apple",verified.Subject);require.Equal(t,"synthetic-existing-apple",data.Metadata.Subject)
 _,_,err=provider.ParseIDToken(ctx,discovered,&oidc.Config{ClientID:"different-app"},signed,provider.ParseIDTokenOptions{})
 require.Error(t,err,"wrong audience must still fail under native-only configuration")

 cfg.External.Apple.Enabled=false;before=calls.Load()
 _,_,_,_,_,err=params.getProvider(ctx,nil,cfg,req,cache)
 require.Error(t,err);require.Equal(t,before,calls.Load(),"disabled Apple remains denied without discovery")

 // Positive control: adding an OAuth secret changes the boundary. Do not claim
 // native-only protection if an operator later enables that second path.
 cfg.External.Apple.Enabled=true;cfg.External.Apple.Secret="fixture-only-not-an-Apple-secret"
 oauth,err:=provider.NewAppleProvider(ctx,cfg.External.Apple,cache)
 require.NoError(t,err);require.NotNil(t,oauth)
}

// Real native ID-token HTTP API on disposable official Auth/PG. Its inputs are
// signed fixture credentials and explicitly reserved synthetic identities.
// It proves transaction/session behavior, not a production enrollment adapter.
func TestSKOAppleNativeLinkOriginalSession(t *testing.T){
 api,config,err:=setupAPIForTest();require.NoError(t,err);defer api.db.Close()
 require.NoError(t,api.db.RawQuery("drop schema if exists apple_owner_policy cascade").Exec())
 sql,err:=os.ReadFile(os.Getenv("SKO_APPLE_POLICY_FILE"));require.NoError(t,err)
 require.NoError(t,api.db.RawQuery(string(sql)).Exec())
 defer func(){require.NoError(t,api.db.RawQuery("drop schema if exists apple_owner_policy cascade").Exec())}()
 require.NoError(t,api.db.RawQuery("create table apple_owner_policy.company_snapshot(user_id uuid primary key,company_id uuid not null,role text not null)").Exec())
 defer func(){require.NoError(t,api.db.RawQuery("drop table apple_owner_policy.company_snapshot").Exec())}()
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
  models.TruncateAll(api.db)
  require.NoError(t,api.db.RawQuery("truncate apple_owner_policy.subject_permits,apple_owner_policy.protected_users,apple_owner_policy.rollout,apple_owner_policy.company_snapshot").Exec())
  owner,err:=models.NewUser("","existing-google@example.test","fixture-primary-password",config.JWT.Aud,map[string]interface{}{"full_name":"existing name","custom_field":"preserved"});require.NoError(t,err)
  confirmed:=time.Now();owner.EmailConfirmedAt=&confirmed;owner.AppMetaData=models.JSONMap{"provider":"google","providers":[]string{"google"}};require.NoError(t,api.db.Create(owner))
  google,err:=models.NewIdentity(owner,"google",map[string]interface{}{"sub":"existing-google-sub","email":"existing-google@example.test","email_verified":true});require.NoError(t,err);require.NoError(t,api.db.Create(google))
  require.NoError(t,api.db.RawQuery("insert into apple_owner_policy.protected_users values(?)",owner.ID).Exec())
  require.NoError(t,api.db.RawQuery("insert into apple_owner_policy.rollout values(true,true)").Exec())
  if tc.permit{require.NoError(t,api.db.RawQuery("insert into apple_owner_policy.subject_permits values('verified-native-subject',?)",owner.ID).Exec())}
  require.NoError(t,api.db.RawQuery("insert into apple_owner_policy.company_snapshot values(?,'00000000-0000-0000-0000-000000000099','owner')",owner.ID).Exec())
  originalSession,err:=models.NewSession(owner.ID,nil);require.NoError(t,err);require.NoError(t,api.db.Create(originalSession))
  originalRequest:=httptest.NewRequest(http.MethodPost,"/token?grant_type=password",nil)
  originalToken,_,err:=api.generateAccessToken(originalRequest,api.db,owner,&originalSession.ID,models.PasswordGrant);require.NoError(t,err)
  snapshot:=func()string{var state string;require.NoError(t,api.db.RawQuery("select jsonb_build_object('user',(select jsonb_build_object('id',id,'email',email,'metadata',raw_user_meta_data)from auth.users where id=?),'google',(select to_jsonb(i)from auth.identities i where id=?),'company',(select to_jsonb(c)from apple_owner_policy.company_snapshot c where user_id=?))::text",owner.ID,google.ID,owner.ID).First(&state));return state}
  before:=snapshot()
  count:=func(table string)int{var n int;require.NoError(t,api.db.RawQuery("select count(*)from auth."+table).First(&n));return n}
  users,identities,sessions:=count("users"),count("identities"),count("sessions")
  rawNonce:=strings.Repeat("n",43);hash:=sha256.Sum256([]byte(rawNonce));now:=time.Now().Unix()
  claims:=jwt.MapClaims{"iss":"https://appleid.apple.com","aud":"com.skworks.skWorks","sub":"verified-native-subject","iat":now,"exp":now+600,"nonce":fmt.Sprintf("%x",hash),"email":"private-relay@example.test","email_verified":true}
  token:=jwt.NewWithClaims(jwt.SigningMethodRS256,claims);token.Header["kid"]="sko-synthetic";signed,err:=token.SignedString(key);require.NoError(t,err)
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
  }else{
   require.NotEqual(t,http.StatusOK,response.Code)
   require.Equal(t,users,count("users"));require.Equal(t,identities,count("identities"));require.Equal(t,sessions,count("sessions"))
  }
  require.Equal(t,before,snapshot(),"original UID/email/profile/Google identity/company preserved")
  original:=httptest.NewRequest(http.MethodGet,"http://localhost/user",nil);original.Header.Set("Authorization","Bearer "+originalToken);stillLive:=httptest.NewRecorder();api.handler.ServeHTTP(stillLive,original);require.Equal(t,http.StatusOK,stillLive.Code,"original session remains usable")
 })}
}
