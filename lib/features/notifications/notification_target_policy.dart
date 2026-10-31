/// Notification links require their saved request/invoice UUID. Ordinary menu
/// entry points may still omit a target and open the complete list.
/// Dedicated map, invitation and vehicle pages validate their own saved targets.
bool notificationTargetIsValid(String? actionKey, String? actionId) {
  const requiredTargets = <String>{
    'site_share_approval',
    'site_order_package',
    'paid_leave_request',
    'route_billing_quantity_request',
    'qualification_photo_request',
    'daily_report_edit_request',
    'checkout_report_registration',
    'site_information_request',
    'site_information_request_result',
    'attendance_correction_request',
    'worker_personnel_change',
    'invoice_approval',
    'expense_review_request',
    'expense_review_completed',
  };
  if (!requiredTargets.contains(actionKey)) return true;
  return actionId != null &&
      RegExp(
        r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$',
      ).hasMatch(actionId);
}
