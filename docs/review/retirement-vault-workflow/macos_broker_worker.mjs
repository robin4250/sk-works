import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { pathToFileURL } from 'node:url';
import { macosRenderer } from './macos_renderer.mjs';
import { runMacRetirementJobs } from './macos_job_runner.mjs';

const exec = promisify(execFile);
const uuid = /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/;

export async function runBrokerWorker({ origin, readToken, renderer, signal, retryDelay,
  fetchImpl = fetch }) {
  const address = new URL(origin);
  const basePath = address.pathname === '/' ? '' : address.pathname;
  if (address.protocol !== 'https:' || address.username || address.password ||
      address.search || address.hash ||
      !['','/functions/v1/retirement-render-broker'].includes(basePath)) {
    throw Error('retirement_broker_origin_invalid');
  }

  async function request(path, body, type, lease) {
    const token = await readToken();
    if (!/^[A-Za-z0-9._-]{20,256}$/.test(token)) throw Error('retirement_broker_token_invalid');
    return fetchImpl(address.origin + basePath + path, {
      method: 'POST', redirect: 'error', cache: 'no-store',
      signal: AbortSignal.any([signal, AbortSignal.timeout(20000)]),
      headers: {
        authorization: 'Bearer ' + token, 'content-type': type,
        ...(lease ? {'x-sko-render-lease':lease} : {}),
      },
      body,
    });
  }

  return runMacRetirementJobs({
    signal, retryDelay,
    async claim() {
      const response = await request('/render/claim', '{}', 'application/json');
      if (response.status === 204) return null;
      if (response.status !== 200 || !response.body) {
        await response.body?.cancel();
        throw Error('retirement_broker_claim_failed');
      }
      const chunks = [];
      let length = 0;
      for await (const chunk of response.body) {
        length += chunk.byteLength;
        if (length > 1024 * 1024) throw Error('retirement_broker_job_too_large');
        chunks.push(chunk);
      }
      const job = JSON.parse(Buffer.concat(chunks).toString('utf8'));
      if (!uuid.test(job.jobId) || !uuid.test(job.lease) ||
          !['own_payroll','own_attendance'].includes(job.kind) ||
          !job.plan || !job.snapshot) throw Error('retirement_broker_bad_job');
      return job;
    },
    async processJob(job) {
      const render = job.kind === 'own_payroll' ? renderer.renderPayroll : renderer.renderAttendance;
      const bytes = await render(job.snapshot, job.plan);
      signal.throwIfAborted();
      const response = await request('/render/result/' + job.jobId, bytes, 'application/pdf', job.lease);
      await response.body?.cancel();
      if (response.status !== 204) throw Error('retirement_broker_publish_failed');
    },
  });
}

export async function main(env = process.env) {
  const controller = new AbortController();
  process.once('SIGTERM', () => controller.abort());
  process.once('SIGINT', () => controller.abort());
  await runBrokerWorker({
    origin: env.SKO_RETIREMENT_BROKER,
    renderer: macosRenderer({executable:env.SKO_RETIREMENT_RENDERER,
      privateSpool:env.SKO_RETIREMENT_PRIVATE_SPOOL}),
    signal: controller.signal,
    retryDelay: 15000,
    async readToken() {
      const {stdout}=await exec('/usr/bin/security', ['find-generic-password','-w','-s',
        'jp.sko.retirement-renderer'], {timeout:4000,maxBuffer:2048});
      return stdout.trim();
    },
  });
}


if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch(() => {
    process.stderr.write('SKO retirement renderer could not start.\n');
    process.exitCode = 1;
  });
}
