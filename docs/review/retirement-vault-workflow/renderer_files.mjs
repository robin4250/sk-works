import { mkdtemp, readFile, rm, stat, writeFile } from 'node:fs/promises';
import { isAbsolute, join } from 'node:path';

export function renderInPrivateDirectory({ invoke, fixtureRoot }) {
  if (!isAbsolute(fixtureRoot)) throw Error('retirement_renderer_paths');
  async function render(kind, snapshot, plan) {
    const dir = await mkdtemp(join(fixtureRoot, 'sko-retirement-render-'));
    try {
      const input = join(dir, 'input.json');
      const output = join(dir, 'output.pdf');
      const { ownerId, workerId, companyId, cutoff } = plan;
      const request = JSON.stringify({ kind, snapshot, ownerId, workerId, companyId, cutoff });
      if (Buffer.byteLength(request) > 1024 * 1024) throw Error('retirement_renderer_input_size');
      await writeFile(input, request, { flag:'wx', mode:0o600 });
      try {
        await invoke(input, output);
      } catch {
        throw Error('retirement_renderer_failed');
      }
      const metadata = await stat(output);
      if (!metadata.isFile() || metadata.size > 6 * 1024 * 1024) {
        throw Error('retirement_renderer_output_size');
      }
      const bytes = await readFile(output);
      if (bytes.subarray(0,5).toString() !== '%PDF-') throw Error('retirement_renderer_invalid_pdf');
      return bytes;
    } finally {
      await rm(dir, { recursive:true, force:true });
    }
  }
  return {
    renderPayroll: (snapshot, plan) => render('own_payroll', snapshot, plan),
    renderAttendance: (snapshot, plan) => render('own_attendance', snapshot, plan),
  };
}
