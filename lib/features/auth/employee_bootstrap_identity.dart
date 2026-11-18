import 'package:supabase_flutter/supabase_flutter.dart';

const employeeExistingAccountClaimEnabled =
    bool.fromEnvironment('SKO_EMPLOYEE_EXISTING_ACCOUNT_CLAIM_ENABLED');

bool hasEmployeeBootstrapEmail(User user) =>
    user.appMetadata['sko_employee_bootstrap'] == true &&
    (user.email?.endsWith('@employee-login.sko.invalid') ?? false);
