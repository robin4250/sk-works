-- Disposable SQL fixture only. Run after the review-only function installation.
begin;
do $fixture$
declare
  provider text;
  payload jsonb;
  response jsonb;
  invalid jsonb;
begin
  -- Existing signup providers retain their current path. No metadata copying.
  foreach provider in array array['google','email','phone'] loop
    payload := jsonb_build_object('user', jsonb_build_object(
      'app_metadata', jsonb_build_object('provider',provider,'providers',jsonb_build_array(provider)),
      'user_metadata',jsonb_build_object('provider','apple')));
    response := private.apple_existing_account_signup_guard(payload);
    assert response = '{}'::jsonb, 'ordinary provider was changed';
  end loop;

  payload := '{"user":{"app_metadata":{"provider":"apple","providers":["apple"]},"user_metadata":{"provider":"google"}}}';
  response := private.apple_existing_account_signup_guard(payload);
  assert response->'error'->>'http_code' = '403', 'Apple signup not blocked';

  payload := '{"user":{"app_metadata":{"provider":"google","providers":["google","apple"]}}}';
  assert private.apple_existing_account_signup_guard(payload)->'error'->>'http_code' = '403',
    'ambiguous provider list not blocked';

  foreach invalid in array array[
    null::jsonb, 'null'::jsonb, '[]'::jsonb, '{}'::jsonb,
    '{"user":{"user_metadata":{"provider":"google"}}}'::jsonb,
    '{"user":{"app_metadata":{"provider":"google","providers":"google"}}}'::jsonb,
    '{"user":{"app_metadata":{"provider":"google","providers":[]}}}'::jsonb,
    '{"user":{"app_metadata":{"provider":"","providers":[""]}}}'::jsonb
  ] loop
    assert private.apple_existing_account_signup_guard(invalid)->'error'->>'http_code' = '403',
      'malformed event not blocked';
  end loop;

  assert has_function_privilege('supabase_auth_admin',
    'private.apple_existing_account_signup_guard(jsonb)','execute');
  assert has_schema_privilege('supabase_auth_admin','private','usage');
  assert not has_function_privilege('anon',
    'private.apple_existing_account_signup_guard(jsonb)','execute');
  assert not has_function_privilege('authenticated',
    'private.apple_existing_account_signup_guard(jsonb)','execute');
end
$fixture$;
rollback;
