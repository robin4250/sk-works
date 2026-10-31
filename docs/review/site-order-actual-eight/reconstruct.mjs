// Disposable reconstruction from already-public, immutable input files only.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
export const hash = (kind, value) => createHash(kind).update(value).digest('hex');
const escape = value => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
export function exactStatement(source, signature, md5) {
  const name = signature.split('(')[0];
  const pattern = new RegExp('create\\s+(?:or\\s+replace\\s+)?function\\s+' + escape(name) + '\\s*\\([\\s\\S]*?\\bas\\s+(\\$[\\w]*\\$)([\\s\\S]*?)\\1\\s*;', 'gi');
  const matches = [...source.matchAll(pattern)].filter(match => hash('md5', match[2]) === md5);
  assert.equal(matches.length, 1, 'one exact public function statement required');
  return {sql: matches[0][0].replace(/^create\s+(?:or\s+replace\s+)?function/i, 'create or replace function'), body: matches[0][2]};
}
export async function reconstruct(read, contract) {
  const sources = {};
  for (const [file, expected] of Object.entries(contract.files)) {
    sources[file] = await read(file);
    assert.equal(hash('sha256', sources[file]), expected, 'public source hash mismatch');
  }
  const generic = Object.entries(contract.generic_sources).map(([signature, file]) => {
    const expected = contract.functions.find(item => item.signature === signature);
    return {signature, ...exactStatement(sources[file], signature, expected.source_md5)};
  });
  const signature = 'private.document_company_seal_snapshot(jsonb,uuid,boolean)';
  const base = exactStatement(sources[contract.seal_base], signature, contract.seal_base_body_md5);
  const patches = sources[contract.seal_patch].match(/DO \$patch_snapshot\$[\s\S]*?END \$patch_snapshot\$;/g) ?? [];
  assert.equal(patches.length, 1, 'one original public patch required');
  const patch = patches[0];
  assert.equal(hash('sha256', patch), contract.seal_patch_statement_sha256);
  const anchor = patch.match(/anchor:='([^']+)';/)?.[1];
  const replacement = patch.match(/EXECUTE replace\(definition,anchor,\$body\$([\s\S]*?)\$body\$\);/)?.[1];
  const declaration = patch.match(/definition:=replace\(definition,'([^']+)','([^']+)'\);/);
  assert.ok(anchor && replacement && declaration, 'original patch operands required');
  assert.equal(base.body.split(anchor).length - 1, 1);
  assert.equal(base.body.split(declaration[1]).length - 1, 1);
  const body = base.body.replace(declaration[1], declaration[2]).replace(anchor, replacement);
  const expected = contract.functions.find(item => item.signature === signature).source_md5;
  assert.equal(hash('md5', body), expected, 'reconstructed seal body differs');
  return {generic, sealBase: base.sql, sealPatch: patch, sealBody: body};
}
