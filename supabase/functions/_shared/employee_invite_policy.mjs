// Role assignment and approval duty are independent. This grants no access;
// only the authorized administrator's requested flags reach onboarding storage.
/**
 * @param {{requestedRole?: unknown, requestedApprovalAssignee?: unknown,
 * replaceApprovalAssigneeUserId?: unknown} | null | undefined} payload
 * @param {string} callerRole
 * @returns {{error: string, status: number} | {requestedRole: 'viewer' | 'manager',
 * requestedApprovalAssignee: boolean, replaceApprovalAssigneeUserId: string | null}}
 */
export function employeeInvitePolicy(payload, callerRole) {
  const requestedRole = payload?.requestedRole ?? 'viewer';
  if (requestedRole !== 'viewer' && requestedRole !== 'manager') {
    return { error: '従業員の役割を確認してください。', status: 400 };
  }
  const requestedApprovalAssignee = payload?.requestedApprovalAssignee === true;
  const replaceApprovalAssigneeUserId =
    typeof payload?.replaceApprovalAssigneeUserId === 'string' &&
      payload.replaceApprovalAssigneeUserId.trim().length > 0
      ? payload.replaceApprovalAssigneeUserId.trim() : null;
  if (!['owner', 'admin'].includes(callerRole) &&
      (requestedRole !== 'viewer' || requestedApprovalAssignee ||
        replaceApprovalAssigneeUserId !== null)) {
    return { error: 'サブ管理者・承認担当者の指定は管理者だけが行えます。', status: 403 };
  }
  if (replaceApprovalAssigneeUserId !== null && !requestedApprovalAssignee) {
    return { error: '承認担当者の選択を確認してください。', status: 400 };
  }
  return { requestedRole, requestedApprovalAssignee, replaceApprovalAssigneeUserId };
}
