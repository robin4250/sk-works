import { serverAccountActivity } from '../_shared/account_activity.mjs';
import { createDeletionInspection } from '../_shared/account_deletion_inspection.mjs';
import { serverAccountAccess } from '../_shared/account_access.mjs';
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const encoder = new TextEncoder();

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
      "Referrer-Policy": "no-referrer",
    },
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

  const membershipResponse = await serviceFetch(
    "/rest/v1/company_members?user_id=eq." +
      encodeURIComponent(caller.id) +
      "&select=company_id,role&limit=1",
    { method: "GET" },
  );
  if (!membershipResponse.ok) {
    return json({ error: "会社情報を確認できませんでした。" }, 500);
  }
  const memberships = await membershipResponse.json();
  if (!Array.isArray(memberships) || memberships.length === 0) {
    return json({ error: "従業員登録は会社メンバーのみ利用できます。" }, 403);
  }
  const companyId = memberships[0].company_id;
  const callerRole = String(memberships[0].role ?? "viewer");
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
    if (!Array.isArray(workers) || workers.length === 0) {
      return json({ error: "対象の従業員が見つかりません。" }, 404);
    }
    existingWorker = workers[0];
    if (existingWorker.user_id) {
      return json({ error: "この従業員は初回登録作成済みです。" }, 409);
    }
    name = String(existingWorker.name ?? "").trim();
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
  if (!authUserId) return json({ error: "利用者IDを作成できませんでした。" }, 500);

  let persistedWorkerId: string | null = workerId;
  let linkedExistingWorker = false;
  let newWorkerCreated = false;
  let persistenceStage = "worker";
  let persistenceStatus: number | null = null;
  try {
    if (existingWorker && persistedWorkerId) {
      const workerResponse = await serviceFetch(
        "/rest/v1/workers?id=eq." + encodeURIComponent(persistedWorkerId) +
          "&company_id=eq." + encodeURIComponent(companyId) + "&user_id=is.null&select=id",
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
      // A successful response may still have an unreadable body. Cleanup is
      // conditional on the new Auth ID, so never touches a concurrent owner.
      linkedExistingWorker = true;
      const linkedRows = await workerResponse.json();
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
      newWorkerCreated = true;
      const workers = await workerResponse.json();
      persistedWorkerId = workers?.[0]?.id ?? null;
    }
    if (!persistedWorkerId) throw new Error("worker id missing");

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
    const inviteId = invites?.[0]?.id;
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
          deliveryMessage = "SMS送信サービスへ接続できませんでした。";
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
    return json({
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
    // Existing employees must never be deleted when a link attempt fails.
    // Undo only this attempt's successful linkage; concurrent reassignment wins.
    if ((persistedWorkerId && linkedExistingWorker) || newWorkerCreated) {
      try {
        const cleanupResponse = await serviceFetch(
          "/rest/v1/workers?company_id=eq." + encodeURIComponent(companyId) +
            (persistedWorkerId ? "&id=eq." + encodeURIComponent(persistedWorkerId) : "") +
            "&user_id=eq." + encodeURIComponent(authUserId),
          linkedExistingWorker
            ? { method: "PATCH", body: JSON.stringify({ user_id: null, status: existingWorker.status }) }
            : { method: "DELETE" },
        );
        if (!cleanupResponse.ok) {
          console.error("employee invite worker cleanup failed", cleanupResponse.status);
        }
      } catch {
        console.error("employee invite worker cleanup failed");
      }
    }
    // A failed worker cleanup must not skip cleanup of the Auth user created here.
    try {
      const cleanupResponse = await serviceFetch(
        "/auth/v1/admin/users/" + encodeURIComponent(authUserId),
        { method: "DELETE" },
      );
      if (!cleanupResponse.ok) {
        console.error("employee invite auth cleanup failed", cleanupResponse.status);
      }
    } catch {
      console.error("employee invite auth cleanup failed");
    }
    return json({ error: "従業員登録を保存できませんでした。" }, 500);
  }
});


