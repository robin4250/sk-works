// Planning only. Callers must supply server-resolved identities and separately
// enforce live sessions, representative approval, feature gates and atomic writes.
const id = (x) => typeof x === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(x);
const fail = (why) => { throw new Error(why); };
export function planCompanyLink({ linkRequested, sourceCompany, targetCompany,
  selectedPartner, reciprocalDirectory, existingRequests, connections }) {
  if (typeof linkRequested !== 'boolean') fail('explicit_choice_required');
  if (!id(sourceCompany?.id) || !id(targetCompany?.id) || sourceCompany.id === targetCompany.id) fail('invalid_company_pair');
  if (!id(selectedPartner?.id) || selectedPartner.companyId !== sourceCompany.id ||
      selectedPartner.linkedCompanyId !== targetCompany.id) fail('verified_existing_partner_required');
  // The NO branch does not create a relationship, trade entry or disclosure.
  if (!linkRequested) return Object.freeze({ kind: 'affiliation_only', createCompany: false, discloseDocuments: false });
  if (![reciprocalDirectory, existingRequests, connections].every(Array.isArray)) fail('relationship_state_required');
  const sourceId = sourceCompany.id, targetId = targetCompany.id;
  if (reciprocalDirectory.some(x => x.companyId !== targetId || !id(x.id))) fail('directory_scope_mismatch');
  if (existingRequests.some(x => !((x.senderId === sourceId && x.targetId === targetId) || (x.senderId === targetId && x.targetId === sourceId)))) fail('request_scope_mismatch');
  if (connections.some(x => !((x.parentId === sourceId && x.childId === targetId) || (x.parentId === targetId && x.childId === sourceId)))) fail('connection_scope_mismatch');
  const linked = reciprocalDirectory.filter(x => x.linkedCompanyId === sourceId);
  if (linked.length > 1) fail('duplicate_linked_directory');
  let entry = linked[0];
  if (!entry) {
    const corp = sourceCompany.corporateNumber;
    const byCorp = typeof corp === 'string' && /^\d{13}$/.test(corp)
      ? reciprocalDirectory.filter(x => x.linkedCompanyId == null && x.corporateNumber === corp) : [];
    if (byCorp.length > 1) fail('duplicate_corporate_number');
    entry = byCorp[0];
    if (!entry && reciprocalDirectory.some(x => x.linkedCompanyId == null &&
      typeof x.name === 'string' && typeof sourceCompany.name === 'string' &&
      x.name.trim().toLowerCase() === sourceCompany.name.trim().toLowerCase())) fail('unverified_same_name');
  }
  if (entry && !['customer', 'subcontractor', 'both'].includes(entry.role)) fail('invalid_directory_role');
  const pending = existingRequests.filter(x => x.status === 'pending');
  if (pending.length > 1) fail('duplicate_pending_request');
  const accepted = connections.filter(x => x.status === 'accepted');
  if (accepted.length > 1) fail('ambiguous_connection');
  // Preserve the existing reciprocal approval path. Nothing here grants access.
  const roleReady = entry && ['customer', 'both'].includes(entry.role);
  return Object.freeze({ kind: accepted.length && roleReady ? 'already_linked'
    : pending.length ? 'reuse_pending_request' : 'request_reciprocal_approval',
    reciprocalDirectoryId: entry?.id ?? null,
    directoryAction: entry ? 'reuse_preserve_contacts' : 'create_after_approval_from_canonical_company',
    createCompany: false, discloseDocuments: false,
    requiresServerRecheck: true });
}
