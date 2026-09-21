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
  if (req.method !== "POST") return json({ error: "Method Not Allowed" }, 405);

  const caller = await callerUser(req);
  if (!caller?.id) return json({ error: "authentication required" }, 401);

  let payload: any;
  try {
    payload = await req.json();
  } catch {
    return json({ error: "invalid JSON" }, 400);
  }

  const name = typeof payload?.name === "string" ? payload.name.trim() : "";
  if (!name) return json({ error: "名前を入力してください。" }, 400);

  let phone: string;
  try {
    phone = normalizeJapaneseMobile(String(payload?.phone ?? ""));
  } catch (error) {
    return json({ error: String(error instanceof Error ? error.message : error) }, 400);
  }

  const membershipResponse = await serviceFetch(
    "/rest/v1/company_members?user_id=eq." +
      encodeURIComponent(caller.id) +
      "&select=company_id&limit=1",
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
    const body = await authResponse.text();
    console.error("employee auth create failed", authResponse.status, body);
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

  let workerId: string | null = null;
  try {
    const workerResponse = await serviceFetch("/rest/v1/workers?select=id", {
      method: "POST",
      headers: { Prefer: "return=representation" },
      body: JSON.stringify({
        company_id: companyId,
        affiliation: "employee",
        name,
        phone,
        status: "inactive",
        user_id: authUserId,
      }),
    });
    if (!workerResponse.ok) throw new Error(await workerResponse.text());
    const workers = await workerResponse.json();
    workerId = workers?.[0]?.id ?? null;
    if (!workerId) throw new Error("worker id missing");

    const inviteResponse = await serviceFetch(
      "/rest/v1/employee_registration_invites",
      {
        method: "POST",
        headers: { Prefer: "return=representation" },
        body: JSON.stringify({
          company_id: companyId,
          worker_id: workerId,
          auth_user_id: authUserId,
          name,
          phone_e164: phone,
          created_by: caller.id,
        }),
      },
    );
    if (!inviteResponse.ok) throw new Error(await inviteResponse.text());

    const invites = await inviteResponse.json();
    const inviteId = invites?.[0]?.id;
    const qrPayload = JSON.stringify({
      type: "sko_employee_invite",
      inviteId,
      phone,
      password,
    });

    return json({
      inviteId,
      name,
      phone,
      temporaryPassword: password,
      qrPayload,
    });
  } catch (error) {
    console.error("employee invite persistence failed", error);
    if (workerId) {
      await serviceFetch(
        "/rest/v1/workers?id=eq." + encodeURIComponent(workerId),
        { method: "DELETE" },
      );
    }
    await serviceFetch("/auth/v1/admin/users/" + encodeURIComponent(authUserId), {
      method: "DELETE",
    });
    return json({ error: "従業員登録を保存できませんでした。" }, 500);
  }
});
