package api

import (
 "context"
 "crypto/rand"
 "crypto/rsa"
 "encoding/base64"
 "encoding/json"
 "fmt"
 "io"
 "net/http"
 "net/http/httptest"
 "strings"
 "sync/atomic"
 "testing"
 "time"

 "github.com/coreos/go-oidc/v3/oidc"
 "github.com/golang-jwt/jwt/v5"
 "github.com/stretchr/testify/require"
 "github.com/supabase/auth/internal/api/provider"
 "github.com/supabase/auth/internal/conf"
)

type skoAppleOfflineTransport func(*http.Request)(*http.Response,error)
func (f skoAppleOfflineTransport) RoundTrip(r *http.Request)(*http.Response,error){return f(r)}

// Configuration/provider proof only. No account/identity/session write and no
// external connection. This does not prove hosted configuration or safe enrollment.
func TestSKOAppleNativeOnlyConfigurationBoundary(t *testing.T){
 key,err:=rsa.GenerateKey(rand.Reader,2048);require.NoError(t,err)
 const bundle="com.skworks.skWorks"
 const issuer="https://appleid.apple.com"
 var calls atomic.Int32
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
 ctx:=oidc.ClientContext(context.Background(),client)
 cfg:=&conf.GlobalConfiguration{}
 cfg.External.Apple.Enabled=true
 cfg.External.Apple.ClientID=[]string{bundle}
 cfg.External.Apple.RedirectURI="https://callback.example.invalid/auth/v1/callback"
 cfg.External.Apple.Secret=""
 cache:=provider.NewOIDCProviderCache(time.Minute)
 before:=calls.Load()
 _,err=provider.NewAppleProvider(ctx,cfg.External.Apple,cache)
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
