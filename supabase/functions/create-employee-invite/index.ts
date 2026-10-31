import { serverAccountActivity } from '../_shared/account_activity.mjs';
import { createDeletionInspection } from '../_shared/account_deletion_inspection.mjs';
import { serverAccountAccess } from '../_shared/account_access.mjs';
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const encoder = new TextEncoder();

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8" },
  });
}

function normalizeJapaneseMobile(raw: string) {
  const trimmed = raw.trim();
  const digits = trimmed.replace(/\D/g, "");
  if (/^81(?:70|80|90)\d{8}$/.test(digits)) return "+" + digits;
  if (/^0(?:70|80|90)\d{8}$/.test(digits)) return "+81" + digits.slice(1);
  throw new Error("070 / 080 / 090から始まる携帯電話番号を入力してください。");
}

function temporaryPassword() {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789";
  const bytes = crypto.getRandomValues(new Uint8Array(14));
  let result = "SKO-";
  for (const byte of bytes) result += alphabet[byte % alphabet.length];
  return result;
}

async function serviceFetch(path: string, init: RequestInit = {}) {
  const url = Deno.env.get("SUPABASE_URL");
  const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceRole) throw new Error("Supabase service configuration missing");

  return fetch(url + path, {
    ...init,
    headers: {
      apikey: serviceRole,
      Authorization: "Bearer " + serviceRole,
      "Content-Type": "application/json",
      ...(init.headers ?? {}),
    },
  });
}

async function employeePhoneProviderEnabled() {
  let reader: ReadableStreamDefaultReader<Uint8Array> | undefined;
  try {
    const response = await serviceFetch("/auth/v1/settings", {
      method: "GET", redirect: "error", signal: AbortSignal.timeout(10000),
    });
    if (!response.ok || !response.body) return false;
    const declared = response.headers.get("content-length");
    if (declared !== null && (!/^\d+$/.test(declared) || Number(declared) > 16384)) return false;
    reader = response.body.getReader();
    const chunks: Uint8Array[] = [];
    let length = 0;
    while (true) {
      const next = await reader.read();
      if (next.done) break;
      if (length + next.value.byteLength > 16384) return false;
      chunks.push(next.value);
      length += next.value.byteLength;
    }
    const bytes = new Uint8Array(length);
    let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
    const value = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
    return value !== null && typeof value === "object" && value.external?.phone === true;
  } catch {
    return false;
  } finally {
    if (reader) { await reader.cancel().catch(() => {}); reader.releaseLock(); }
  }
}

const accessRpc = async (name: string, args: unknown) => {
  const response = await serviceFetch('/rest/v1/rpc/' + name, {
    method: 'POST', body: JSON.stringify(args), signal: AbortSignal.timeout(10000),
  });
  if (!response.ok) throw Error('account_access_unavailable');
  return await response.json();
};
const checkAccountAccess = serverAccountAccess(accessRpc);
const inspectDeletion = createDeletionInspection({serviceKey:Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')??'',rpc:accessRpc,checkAccess:checkAccountAccess});
const accountActivity = serverAccountActivity(accessRpc);
async function accessFailure(userId: string) {
  try {
    return await checkAccountAccess(userId) ? null
      : json({ error: 'アカウントの利用を停止しています。' }, 403);
  } catch {
    return json({ error: '利用権限を確認できませんでした。時間をおいてお試しください。' }, 503);
  }
}

async function callerUser(req: Request) {
  const url = Deno.env.get("SUPABASE_URL");
  const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const authorization = req.headers.get("authorization") ?? "";
  if (!url || !serviceRole || !authorization.startsWith("Bearer ")) return null;

  const response = await fetch(url + "/auth/v1/user", {
    headers: {
      apikey: serviceRole,
      Authorization: authorization,
    },
  });
  if (!response.ok) return null;
  return await response.json();
}

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
function verifiedSession(req: Request, actor: string) {
  // Only called after the same Bearer was verified by Auth /user. Decoding is
  // binding, never signature validation or authorization from body metadata.
  try {
    const token = (req.headers.get('authorization') ?? '').slice(7).split('.');
    if (token.length !== 3) return null;
    const text = token[1].replace(/-/g, '+').replace(/_/g, '/');
    const claims = JSON.parse(atob(text.padEnd(Math.ceil(text.length / 4) * 4, '=')));
    if (claims.sub !== actor || claims.role !== 'authenticated' ||
        !uuid.test(claims.session_id ?? '') || !Number.isFinite(claims.exp) ||
        claims.exp * 1000 <= Date.now()) return null;
    return claims.session_id;
  } catch { return null; }
}
async function inviteContext(actor: string, session: string, company: string) {
  const raw = await accessRpc('employee_invite_operation_context',
    {p_actor: actor, p_session: session, p_company: company});
  if (!raw || typeof raw !== 'object' || raw.version !== 1 ||
      raw.actor_id !== actor || raw.session_id !== session || raw.company_id !== company ||
      !['owner','admin','manager','viewer'].includes(raw.role)) throw Error('invite_context_unavailable');
  return raw;
}

Deno.serve(async (req: Request) => {
  const inspection = await inspectDeletion(req);
  if (inspection) return inspection;
  if (req.method !== "POST") return json({ error: "Method Not Allowed" }, 405);

  const caller = await callerUser(req);
  if (!caller?.id) return json({ error: "authentication required" }, 401);

  const denied = await accessFailure(caller.id);
  if (denied) return denied;

  let payload: any;
  try {
    payload = await req.json();
  } catch {
    return json({ error: "invalid JSON" }, 400);
  }

  let name = typeof payload?.name === "string" ? payload.name.trim() : "";
  let phone = "";
  const workerId =
    typeof payload?.workerId === "string" && payload.workerId.trim().length > 0
      ? payload.workerId.trim()
      : null;
  const deliverSms = payload?.deliverSms === true;

  const sessionId = verifiedSession(req, caller.id);
  const companyId = payload?.companyId;
  if (!sessionId || payload?.sessionId !== sessionId || !uuid.test(companyId ?? '')) {
    return json({error: '対象会社・ログイン状態を確認してください。'}, 403);
  }
  let context: any;
  try { context = await inviteContext(caller.id, sessionId, companyId); }
  catch { return json({error: '招待の利用状態を確認できません。'}, 503); }
  const callerRole = context.role;
  const canAssignManagementRole =
    callerRole === "owner" || callerRole === "admin";

  let existingWorker: any = null;
  if (workerId) {
    if (!canAssignManagementRole) {
      return json({ error: "初回登録の送信は管理者だけが行えます。" }, 403);
    }
    const workerResponse = await serviceFetch(
      "/rest/v1/workers?id=eq." +
        encodeURIComponent(workerId) +
        "&company_id=eq." +
        encodeURIComponent(companyId) +
        "&affiliation=eq.employee&select=id,name,phone,user_id,status&limit=1",
      { method: "GET" },
    );
    if (!workerResponse.ok) {
      return json({ error: "従業員情報を確認できませんでした。" }, 500);
    }
    const workers = await workerResponse.json();
    if (!Array.isArray(workers) || workers.length !== 1 || workers[0]?.id !== workerId) {
      return json({ error: "対象の従業員が見つかりません。" }, 404);
    }
    existingWorker = workers[0];
    if (existingWorker.user_id) {
      return json({ error: "この従業員は初回登録作成済みです。" }, 409);
    }
    name = String(existingWorker.name ?? "").trim();
    if (!name) return json({error: '対象従業員の氏名を確認してください。'}, 409);
    try {
      phone = normalizeJapaneseMobile(String(existingWorker.phone ?? ""));
    } catch (error) {
      return json({ error: String(error instanceof Error ? error.message : error) }, 400);
    }
  } else {
    if (!name) return json({ error: "名前を入力してください。" }, 400);
    try {
      phone = normalizeJapaneseMobile(String(payload?.phone ?? ""));
    } catch (error) {
      return json({ error: String(error instanceof Error ? error.message : error) }, 400);
    }
  }

  if (workerId) {
    try {
      if (typeof payload?.expectedPhone !== 'string' || normalizeJapaneseMobile(payload.expectedPhone) !== phone) {
        return json({error: '対象従業員の電話番号が変わりました。再読み込みしてください。'}, 409);
      }
    } catch { return json({error: '対象従業員の電話番号を確認してください。'}, 409); }
  }

  const requestedRole =
    payload?.requestedRole === "manager" ? "manager" : "viewer";
  const requestedApprovalAssignee =
    payload?.requestedApprovalAssignee === true;
  const replaceApprovalAssigneeUserId =
    typeof payload?.replaceApprovalAssigneeUserId === "string" &&
      payload.replaceApprovalAssigneeUserId.trim().length > 0
      ? payload.replaceApprovalAssigneeUserId.trim()
      : null;

  if (
    !canAssignManagementRole &&
    (requestedRole !== "viewer" || requestedApprovalAssignee ||
      replaceApprovalAssigneeUserId !== null)
  ) {
    return json(
      { error: "サブ管理者・承認担当者の指定は管理者だけが行えます。" },
      403,
    );
  }

  if (requestedApprovalAssignee && requestedRole !== "manager") {
    return json(
      { error: "承認担当者にする場合はサブ管理者を選択してください。" },
      400,
    );
  }

  if (requestedApprovalAssignee) {
    const assigneeResponse = await serviceFetch(
      "/rest/v1/company_approval_assignees?company_id=eq." +
        encodeURIComponent(companyId) +
        "&select=user_id",
      { method: "GET" },
    );
    if (!assigneeResponse.ok) {
      return json({ error: "承認担当者を確認できませんでした。" }, 500);
    }
    const assignees = await assigneeResponse.json();
    const currentIds = Array.isArray(assignees)
      ? assignees.map((row: any) => String(row.user_id))
      : [];

    if (currentIds.length >= 3) {
      if (!replaceApprovalAssigneeUserId) {
        return json(
          {
            error: "承認担当者は最大3名です。現在の担当者から外す人を選んでください。",
            code: "approval_assignee_limit_reached",
          },
          409,
        );
      }
      if (!currentIds.includes(replaceApprovalAssigneeUserId)) {
        return json(
          {
            error: "入れ替え対象の承認担当者が現在の設定と一致しません。",
            code: "approval_assignee_replacement_invalid",
          },
          409,
        );
      }
    }
  }

  const existingInviteResponse = await serviceFetch(
    "/rest/v1/employee_registration_invites?company_id=eq." +
      encodeURIComponent(companyId) +
      "&phone_e164=eq." +
      encodeURIComponent(phone) +
      "&status=not.in.(cancelled,approved)&select=id,status&limit=1",
    { method: "GET" },
  );
  if (!existingInviteResponse.ok) {
    return json({ error: "既存登録を確認できませんでした。" }, 500);
  }
  const existingInvites = await existingInviteResponse.json();
  if (Array.isArray(existingInvites) && existingInvites.length > 0) {
    return json({ error: "この電話番号はすでに登録手続き中です。" }, 409);
  }

  // A QR containing ordinary phone credentials is unusable when this Auth
  // provider is OFF. Fail before creating Auth, worker or invitation records.
  if (!await employeePhoneProviderEnabled()) {
    return json({ error: "電話番号での初回登録は提供設定が未完了です。現在の登録済みログインはそのまま利用できます。" }, 503);
  }

  const changedAccess = await accessFailure(caller.id);
  if (changedAccess) return changedAccess;

  let activityId: string;
  try {
    activityId = await accountActivity.begin(caller.id, 'create-employee-invite');
  } catch {
    return json({ error: '利用権限を確認できませんでした。時間をおいてお試しください。' }, 503);
  }
  // Any unconfirmed remote failure leaves this activity pending for operator review.
  // Recheck live SID, account, exact selected membership and role immediately
  // before creating Auth. This does not make multiple REST writes atomic.
  try {
    const fresh = await inviteContext(caller.id, sessionId, companyId);
    if (fresh.role !== callerRole) throw Error('role_changed');
  } catch { return json({error: '招待の利用状態が変わりました。'}, 403); }
  const password = temporaryPassword();
  const authResponse = await serviceFetch("/auth/v1/admin/users", {
    method: "POST",
    body: JSON.stringify({
      phone,
      password,
      phone_confirm: true,
      app_metadata: {
        sko_registration_type: "employee_invite",
      },
      user_metadata: {
        sko_invited_name: name,
      },
    }),
  });

  if (!authResponse.ok) {
    // Upstream errors may contain personal data; retain only the stage and status.
    console.error("employee auth create failed", authResponse.status);
    return json(
      { error: authResponse.status === 422
          ? "この電話番号はすでにSKOへ登録されています。"
          : "ログイン情報を作成できませんでした。" },
      authResponse.status === 422 ? 409 : 500,
    );
  }

  const authPayload = await authResponse.json();
  const authUserId = authPayload?.id ?? authPayload?.user?.id;
  if (!uuid.test(authUserId ?? '')) return json({ error: "利用者IDを確認できません。結果は未解決です。" }, 500);

  let persistedWorkerId: string | null = workerId;
  let confirmedWorkerCasNoWrite = false;
  let persistenceStage = "worker";
  let persistenceStatus: number | null = null;
  try {
    if (existingWorker && persistedWorkerId) {
      const workerResponse = await serviceFetch(
        "/rest/v1/workers?id=eq." + encodeURIComponent(persistedWorkerId) +
          "&company_id=eq." + encodeURIComponent(companyId) + "&user_id=is.null" +
          "&phone=eq." + encodeURIComponent(existingWorker.phone) +
          "&name=eq." + encodeURIComponent(existingWorker.name) +
          (existingWorker.status == null ? "&status=is.null" : "&status=eq." + encodeURIComponent(existingWorker.status)) +
          "&affiliation=eq.employee&select=id",
        {
          method: "PATCH",
          headers: { Prefer: "return=representation" },
          body: JSON.stringify({
            user_id: authUserId,
            status: "active",
            updated_at: new Date().toISOString(),
          }),
        },
      );
      if (!workerResponse.ok) {
        persistenceStatus = workerResponse.status;
        throw new Error("employee worker persistence failed");
      }
      // HTTP failure or an unreadable body can follow a committed write. Only
      // an exact empty representation proves this CAS did not change a row.
      const linkedRows = await workerResponse.json();
      confirmedWorkerCasNoWrite = Array.isArray(linkedRows) && linkedRows.length === 0;
      if (!Array.isArray(linkedRows) || linkedRows.length !== 1 ||
          linkedRows[0]?.id !== persistedWorkerId) {
        throw new Error("employee worker linkage unconfirmed");
      }
    } else {
      const workerResponse = await serviceFetch("/rest/v1/workers?select=id", {
        method: "POST",
        headers: { Prefer: "return=representation" },
        body: JSON.stringify({
          company_id: companyId,
          affiliation: "employee",
          name,
          phone,
          status: "active",
          user_id: authUserId,
        }),
      });
      if (!workerResponse.ok) {
        persistenceStatus = workerResponse.status;
        throw new Error("employee worker persistence failed");
      }
      const workers = await workerResponse.json();
      if (!Array.isArray(workers) || workers.length !== 1) throw new Error('worker result unknown');
      persistedWorkerId = workers[0]?.id ?? null;
    }
    if (!uuid.test(persistedWorkerId ?? '')) throw new Error("worker id missing");

    persistenceStage = "invite";
    const inviteResponse = await serviceFetch(
      "/rest/v1/employee_registration_invites",
      {
        method: "POST",
        headers: { Prefer: "return=representation" },
        body: JSON.stringify({
          company_id: companyId,
          worker_id: persistedWorkerId,
          auth_user_id: authUserId,
          name,
          phone_e164: phone,
          requested_role: requestedRole,
          requested_approval_assignee: requestedApprovalAssignee,
          replace_approval_assignee_user_id: replaceApprovalAssigneeUserId,
          created_by: caller.id,
        }),
      },
    );
    if (!inviteResponse.ok) {
      persistenceStatus = inviteResponse.status;
      throw new Error("employee invite persistence failed");
    }

    const invites = await inviteResponse.json();
    if (!Array.isArray(invites) || invites.length !== 1 || !uuid.test(invites[0]?.id ?? '')) {
      throw new Error('invite id missing');
    }
    const inviteId = invites[0].id;
    const qrPayload = JSON.stringify({
      type: "sko_employee_invite",
      inviteId,
      phone,
      password,
    });

    let testFlightUrl = "";
    const companyResponse = await serviceFetch(
      "/rest/v1/companies?id=eq." + encodeURIComponent(companyId) +
        "&select=employee_testflight_url&limit=1",
      { method: "GET" },
    );
    if (companyResponse.ok) {
      const companyRows = await companyResponse.json();
      testFlightUrl = String(companyRows?.[0]?.employee_testflight_url ?? "").trim();
    }
    if (!testFlightUrl) {
      testFlightUrl = Deno.env.get("SKO_TESTFLIGHT_URL") ?? "";
    }
    const expectedRawPhone = existingWorker ? existingWorker.phone : phone;
    const verifyRecipient = async () => {
      const current = await serviceFetch('/rest/v1/workers?id=eq.' + encodeURIComponent(persistedWorkerId!) +
        '&company_id=eq.' + encodeURIComponent(companyId) + '&user_id=eq.' + encodeURIComponent(authUserId) +
        '&phone=eq.' + encodeURIComponent(expectedRawPhone) + '&affiliation=eq.employee&select=id,user_id,phone');
      if (!current.ok) throw Error('recipient_binding_unavailable');
      const rows = await current.json();
      if (!Array.isArray(rows) || rows.length !== 1 || rows[0]?.id !== persistedWorkerId ||
          rows[0]?.user_id !== authUserId || rows[0]?.phone !== expectedRawPhone) throw Error('recipient_binding_changed');
    };

    // Never disclose credentials or deliver after context revocation. Existing
    // created rows remain an unresolved operation; no blind recreation/cleanup.
    try {
      const fresh = await inviteContext(caller.id, sessionId, companyId);
      if (fresh.role !== callerRole) throw Error('role_changed');
      await verifyRecipient();
    } catch {
      return json({error: '作成結果は未解決です。再作成せず管理者に確認してください。',
        code: 'invite_result_unknown'}, 409);
    }
    let smsSent = false;
    let deliveryMessage = "";
    if (deliverSms) {
      const webhook = Deno.env.get("SKO_EMPLOYEE_INVITE_SMS_WEBHOOK");
      const webhookToken = Deno.env.get("SKO_EMPLOYEE_INVITE_SMS_WEBHOOK_TOKEN");
      if (!testFlightUrl) {
        deliveryMessage = "TestFlight URLが未設定です。";
      } else if (!webhook) {
        deliveryMessage = "SMS自動送信基盤が未接続です。";
      } else {
        try {
          const headers: Record<string, string> = {
            "Content-Type": "application/json",
          };
          if (webhookToken) headers.Authorization = "Bearer " + webhookToken;
          const deliveryResponse = await fetch(webhook, {
            method: "POST",
            headers,
            body: JSON.stringify({
              to: phone,
              name,
              testFlightUrl,
              temporaryPassword: password,
              qrPayload,
              inviteId,
            }),
          });
          smsSent = deliveryResponse.ok;
          if (!smsSent) {
            deliveryMessage = "SMS送信サービスがエラーを返しました。";
          }
        } catch {
          console.error("employee invite sms delivery failed");
          deliveryMessage = "SMS送信結果は未確認です。再送せず配信状況を確認してください。";
        }
      }
    }

    try {
      await accountActivity.finish(caller.id, activityId);
    } catch {
      // Registration succeeded: never destroy it because bookkeeping failed.
      // The pending activity still prevents deletion until reconciled.
      console.error('employee invite activity completion unconfirmed');
    }
    try {
      const fresh = await inviteContext(caller.id, sessionId, companyId);
      if (fresh.role !== callerRole) throw Error('role_changed');
      await verifyRecipient();
    } catch {
      return json({error: '作成結果は未解決です。再作成せず管理者に確認してください。',
        code: 'invite_result_unknown'}, 409);
    }
    return json({
      actorId: caller.id, sessionId, companyId, workerId: persistedWorkerId, authUserId,
      inviteId,
      name,
      phone,
      temporaryPassword: password,
      qrPayload,
      smsSent,
      testFlightUrl,
      deliveryMessage,
    });
  } catch {
    // Never log upstream details or exception text: either may contain personal data.
    console.error("employee invite persistence failed", persistenceStage, persistenceStatus);
    // Never compensate an uncertain REST write: worker/invite may have
    // committed before the response was lost. Preserve Auth, rows and the
    // pending activity for operator reconciliation; never return credentials.
    // Exact CAS-zero is the only known no-link case. Even then verify BOTH
    // reference sets before deleting only the Auth ID created by this attempt.
    if (confirmedWorkerCasNoWrite && persistenceStage === 'worker') {
      try {
        const workers = await serviceFetch('/rest/v1/workers?user_id=eq.' + encodeURIComponent(authUserId) + '&select=id&limit=1');
        const invites = await serviceFetch('/rest/v1/employee_registration_invites?auth_user_id=eq.' + encodeURIComponent(authUserId) + '&select=id&limit=1');
        if (!workers.ok || !invites.ok) throw Error('reference_read_unknown');
        const workerRows = await workers.json(), inviteRows = await invites.json();
        if (!Array.isArray(workerRows) || !Array.isArray(inviteRows)) throw Error('reference_read_unknown');
        if (workerRows.length === 0 && inviteRows.length === 0) {
          const removed = await serviceFetch('/auth/v1/admin/users/' + encodeURIComponent(authUserId), {method:'DELETE'});
          if (!removed.ok) console.error('employee invite auth cleanup unconfirmed', removed.status);
        }
      } catch { console.error('employee invite auth cleanup unconfirmed'); }
    }
    return json({error: '作成結果は未解決です。再作成せず管理者に確認してください。', code:'invite_result_unknown'}, 409);
  }
});


