import { createHash } from 'node:crypto';
import { execFile } from 'node:child_process';
import { isAbsolute } from 'node:path';
import { promisify } from 'node:util';
import { renderInPrivateDirectory } from './renderer_files.mjs';

const run = promisify(execFile);

// The Flutter PDF library inserts a random document ID. Replace only the
// verified xref trailer field, keeping byte offsets and all page data intact.
function stableArchivePdf(bytes) {
  const tail = bytes.subarray(-128).toString('latin1');
  const end = /startxref\s+(\d+)\s+%%EOF\s*$/.exec(tail);
  const start = Number(end?.[1]);
  if (!Number.isSafeInteger(start) || start < 0 || start >= bytes.length) {
    throw Error('retirement_renderer_xref');
  }
  const xref = bytes.subarray(start, start + 2048).toString('latin1');
  const head = xref.split(/\bstream\r?\n/, 1)[0];
  const field = /\/ID\[<([a-f0-9]{64})><\1>\]/.exec(head);
  if (!/\/Type\s*\/XRef\b/.test(head) || !field) {
    throw Error('retirement_renderer_xref_id');
  }
  const offset = start + field.index + '/ID[<'.length;
  const second = offset + 66;
  const checked = Buffer.from(bytes);
  for (const begin of [offset, second]) checked.fill(0x30, begin, begin + 64);
  const id = createHash('sha256').update(checked).digest('hex');
  for (const begin of [offset, second]) checked.write(id, begin, 64, 'ascii');
  return checked;
}

export function macosRenderer({ executable, privateSpool }) {
  if (process.platform !== 'darwin' || !isAbsolute(executable) ||
      !isAbsolute(privateSpool)) throw Error('retirement_renderer_paths');
  const renderer = renderInPrivateDirectory({
    fixtureRoot: privateSpool,
    invoke: (input, output) => run(executable, [], {
      timeout: 30000,
      maxBuffer: 65536,
      env: {
        TZ:'Asia/Tokyo',
        SKO_RETIREMENT_RENDER_INPUT:input,
        SKO_RETIREMENT_RENDER_OUTPUT:output,
      },
    }),
  });
  return {
    renderPayroll: async (snapshot, plan) => stableArchivePdf(await renderer.renderPayroll(snapshot, plan)),
    renderAttendance: async (snapshot, plan) => stableArchivePdf(await renderer.renderAttendance(snapshot, plan)),
  };
}
