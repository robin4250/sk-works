import 'package:flutter/material.dart';

import 'employee_initial_registration_page.dart';

/// Compatibility entry for saved routes and the initial setup wizard.
class EmployeeRegistrationPage extends StatelessWidget {
  const EmployeeRegistrationPage({super.key, this.allowInvitations = true});

  final bool allowInvitations;

  @override
  Widget build(BuildContext context) => EmployeeInitialRegistrationPage(
        allowInvitations: allowInvitations,
      );
}
