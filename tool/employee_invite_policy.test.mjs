import { strict as assert } from 'node:assert';
import { test } from 'node:test';
import { employeeInvitePolicy } from '../supabase/functions/_shared/employee_invite_policy.mjs';

test('administrator can select a viewer approver without a management promotion', () => {
  for (const caller of ['owner', 'admin']) {
    assert.deepEqual(employeeInvitePolicy({ requestedRole: 'viewer', requestedApprovalAssignee: true }, caller),
      { requestedRole: 'viewer', requestedApprovalAssignee: true, replaceApprovalAssigneeUserId: null });
  }
});
test('sub-admin, ordinary viewer and selected viewer cannot assign new privileges', () => {
  for (const caller of ['manager', 'viewer', 'employee']) {
    assert.equal(employeeInvitePolicy({ requestedApprovalAssignee: true }, caller).status, 403);
    assert.equal(employeeInvitePolicy({ requestedRole: 'manager' }, caller).status, 403);
    assert.equal(employeeInvitePolicy({ replaceApprovalAssigneeUserId: 'existing' }, caller).status, 403);
  }
});
test('ordinary registration stays viewer and malformed role is not coerced', () => {
  assert.equal(employeeInvitePolicy({}, 'viewer').requestedRole, 'viewer');
  assert.equal(employeeInvitePolicy({ requestedRole: 'owner' }, 'admin').status, 400);
  assert.equal(employeeInvitePolicy({ replaceApprovalAssigneeUserId: 'existing' }, 'admin').status, 400);
});
test('replacement keeps exact selected role and selected duty', () => {
  const result = employeeInvitePolicy({ requestedRole: 'manager', requestedApprovalAssignee: true,
    replaceApprovalAssigneeUserId: ' existing ' }, 'admin');
  assert.equal(result.requestedRole, 'manager');
  assert.equal(result.replaceApprovalAssigneeUserId, 'existing');
});
