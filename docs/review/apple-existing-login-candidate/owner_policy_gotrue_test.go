package api

import (
 "net/http"
 "net/http/httptest"
 "os"
 "testing"
 "time"

 "github.com/stretchr/testify/require"
 "github.com/supabase/auth/internal/api/provider"
 "github.com/supabase/auth/internal/models"
 "github.com/supabase/auth/internal/storage"
)

// Runs against an unmodified pinned GoTrue source checkout with its real migrations.
// It exercises the external-account transaction + real token service + PostgreSQL hook.
// Apple signature/credential acquisition is intentionally outside this transaction test.
func TestSKOAppleOwnerPolicyTransaction(t *testing.T) {
 api, config, err := setupAPIForTest()
 require.NoError(t,err)
 defer api.db.Close()
 sql, err := os.ReadFile(os.Getenv("SKO_APPLE_POLICY_FILE"))
 require.NoError(t,err)
 require.NoError(t,api.db.RawQuery(string(sql)).Exec())
 config.DisableSignup=false
 config.Hook.CustomAccessToken.Enabled=true
 config.Hook.CustomAccessToken.URI="pg-functions://postgres/apple_owner_policy/custom_access_token_hook"
 require.NoError(t,config.Hook.CustomAccessToken.PopulateExtensibilityPoint())
 defer func(){config.Hook.CustomAccessToken.Enabled=false}()

 cases:=[]struct{name string;enabled,protect,permit,existingApple,removeApple bool;email,subject string;wantError bool}{
  {name:"default OFF unchanged",protect:true,email:"owner@example.test",subject:"unknown"},
  {name:"owner unknown same email auto link rolls back",enabled:true,protect:true,email:"owner@example.test",subject:"unknown",wantError:true},
  {name:"enrolled existing Apple preserves UID",enabled:true,protect:true,permit:true,existingApple:true,email:"owner@example.test",subject:"reserved"},
  {name:"enrolled manual prepared link preserves UID",enabled:true,protect:true,permit:true,email:"owner@example.test",subject:"reserved"},
  {name:"unlink race reserved subject cannot create new UID",enabled:true,protect:true,permit:true,existingApple:true,removeApple:true,email:"different@example.test",subject:"reserved",wantError:true},
  {name:"reserved subject cannot link to another existing UID",enabled:true,protect:true,permit:true,email:"other@example.test",subject:"reserved",wantError:true},
  {name:"unrelated signup policy unchanged",enabled:true,protect:true,email:"unrelated@example.test",subject:"unrelated"},
 }
 for _,c:=range cases {t.Run(c.name,func(t *testing.T){
  models.TruncateAll(api.db)
  require.NoError(t,api.db.RawQuery("truncate apple_owner_policy.subject_permits,apple_owner_policy.protected_users,apple_owner_policy.rollout").Exec())
  createUser:=func(email,subject string)*models.User{
   u,e:=models.NewUser("",email,"",config.JWT.Aud,nil);require.NoError(t,e)
   now:=time.Now();u.EmailConfirmedAt=&now;require.NoError(t,api.db.Create(u))
   identity,e:=models.NewIdentity(u,"google",map[string]interface{}{"sub":subject,"email":email,"email_verified":true});require.NoError(t,e)
   require.NoError(t,api.db.Create(identity));return u
  }
  owner:=createUser("owner@example.test","owner-google")
  other:=createUser("other@example.test","other-google")
  if c.protect {require.NoError(t,api.db.RawQuery("insert into apple_owner_policy.protected_users values(?)",owner.ID).Exec())}
  if c.permit {require.NoError(t,api.db.RawQuery("insert into apple_owner_policy.subject_permits values('reserved',?)",owner.ID).Exec())}
  if c.enabled {require.NoError(t,api.db.RawQuery("insert into apple_owner_policy.rollout values(true,true)").Exec())}
  if c.existingApple {i,e:=models.NewIdentity(owner,"apple",map[string]interface{}{"sub":"reserved","email":"owner@example.test","email_verified":true});require.NoError(t,e);require.NoError(t,api.db.Create(i))}
  if c.removeApple {require.NoError(t,api.db.RawQuery("delete from auth.identities where provider='apple'").Exec())}
  count:=func(table string)int {var n int;require.NoError(t,api.db.RawQuery("select count(*) from auth."+table).First(&n));return n}
  beforeUsers,beforeIdentities,beforeSessions:=count("users"),count("identities"),count("sessions")
  data:=&provider.UserProvidedData{Metadata:&provider.Claims{Subject:c.subject,Email:c.email,EmailVerified:true},Emails:[]provider.Email{{Email:c.email,Primary:true,Verified:true}}}
  req:=httptest.NewRequest(http.MethodPost,"/token?grant_type=id_token",nil)
  var resultUser *models.User
  err:=api.db.Transaction(func(tx *storage.Connection)error{
   _,u,e:=api.createAccountFromExternalIdentity(tx,req,data,"apple",false);if e!=nil{return e};resultUser=u
   _,e=api.issueRefreshToken(req,http.Header{},tx,u,models.OAuth,models.GrantParams{});return e
  })
  if c.wantError {
   require.Error(t,err)
   require.Equal(t,beforeUsers,count("users"),"failed exchange must roll back new user")
   require.Equal(t,beforeIdentities,count("identities"),"failed exchange must roll back identity")
   require.Equal(t,beforeSessions,count("sessions"),"failed exchange must roll back session")
  } else {
   require.NoError(t,err)
   if c.email=="owner@example.test" {require.Equal(t,owner.ID,resultUser.ID)}
  }
  // Existing Google identities and owner email survive every accepted/denied path.
  google,e:=models.FindIdentityByIdAndProvider(api.db,"owner-google","google");require.NoError(t,e);require.Equal(t,owner.ID,google.UserID)
  google,e=models.FindIdentityByIdAndProvider(api.db,"other-google","google");require.NoError(t,e);require.Equal(t,other.ID,google.UserID)
 })}
}
