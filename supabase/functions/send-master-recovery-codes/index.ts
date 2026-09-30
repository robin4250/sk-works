import "jsr:@supabase/functions-js/edge-runtime.d.ts";

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8" },
  });
}

function defaultKeyFromJson(name: string) {
  const raw = Deno.env.get(name);
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw);
    return typeof parsed?.default === "string" ? parsed.default : null;
  } catch {
    return null;
  }
}

function publishableKey() {
  return defaultKeyFromJson("SUPABASE_PUBLISHABLE_KEYS") ??
    Deno.env.get("SUPABASE_ANON_KEY") ??
    null;
}

function adminKey() {
  const current = defaultKeyFromJson("SUPABASE_SECRET_KEYS");
  if (current) return { value: current, legacyJwt: false };
  const legacy = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (legacy) return { value: legacy, legacyJwt: true };
  return null;
}

async function callerUser(req: Request) {
  const url = Deno.env.get("SUPABASE_URL");
  const apikey = publishableKey();
  const authorization = req.headers.get("authorization") ?? "";
  if (!url || !apikey || !authorization.startsWith("Bearer ")) return null;

  const response = await fetch(url + "/auth/v1/user", {
    headers: { apikey, Authorization: authorization },
  });
  if (!response.ok) return null;
  return await response.json();
}

async function serviceRpc(name: string, body: Record<string, unknown>) {
  const url = Deno.env.get("SUPABASE_URL");
  const key = adminKey();
  if (!url || !key) throw new Error("Supabase service configuration missing");

  const headers: Record<string, string> = {
    apikey: key.value,
    "Content-Type": "application/json",
  };
  if (key.legacyJwt) headers.Authorization = "Bearer " + key.value;

  return fetch(url + "/rest/v1/rpc/" + name, {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
}

function sixDigitCode() {
  const range = 1_000_000;
  const limit = Math.floor(0x1_0000_0000 / range) * range;
  const value = new Uint32Array(1);
  do {
    crypto.getRandomValues(value);
  } while (value[0] >= limit);
  return String(value[0] % range).padStart(6, "0");
}

async function sendRecoveryEmail(params: {
  to: string;
  code: string;
  channelLabel: string;
}) {
  const apiKey = Deno.env.get("RESEND_API_KEY");
  const from = Deno.env.get("MASTER_RECOVERY_FROM_EMAIL");
  if (!apiKey || !from) throw new Error("Master recovery email configuration missing");

  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: "Bearer " + apiKey,
    },
    body: JSON.stringify({
      from,
      to: [params.to],
      subject: "SKO Master 緊急復旧コード",
      html:
        "<p>SKO Master 緊急復旧の確認コードです。</p>" +
        "<p><strong style=\"font-size:24px\">" + params.code + "</strong></p>" +
        "<p>このコードは " + params.channelLabel +
        " 用です。もう一方のメールに届いた別コードも必要です。</p>" +
        "<p>心当たりがない場合は、このメールを破棄してください。</p>",
    }),
  });

  if (!response.ok) {
    console.error("master recovery email delivery failed", response.status);
    throw new Error("recovery email delivery failed");
  }
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "Method Not Allowed" }, 405);

  if (!Deno.env.get("RESEND_API_KEY") ||
      !Deno.env.get("MASTER_RECOVERY_FROM_EMAIL")) {
    return json({ error: "Master復旧メール送信設定が未完了です。" }, 503);
  }

  const caller = await callerUser(req);
  if (!caller?.id) return json({ error: "authentication required" }, 401);

  let primaryCode = sixDigitCode();
  let secondaryCode = sixDigitCode();
  while (secondaryCode === primaryCode) secondaryCode = sixDigitCode();

  const challengeResponse = await serviceRpc(
    "service_create_master_recovery_challenge",
    {
      p_master_user_id: caller.id,
      p_primary_code: primaryCode,
      p_secondary_code: secondaryCode,
      p_ttl_minutes: 15,
    },
  );

  if (!challengeResponse.ok) {
    console.error("master recovery challenge issuance failed", challengeResponse.status);
    return json({ error: "復旧手続きを開始できませんでした。" }, 403);
  }

  const challenge = await challengeResponse.json();
  const primaryEmail = String(challenge?.primary_email ?? "");
  const secondaryEmail = String(challenge?.secondary_email ?? "");
  const challengeId = String(challenge?.challenge_id ?? "");
  const expiresAt = String(challenge?.expires_at ?? "");

  if (!challengeId || !primaryEmail.includes("@") || !secondaryEmail.includes("@")) {
    return json({ error: "復旧先メールを確認できませんでした。" }, 500);
  }

  const results = await Promise.allSettled([
    sendRecoveryEmail({
      to: primaryEmail,
      code: primaryCode,
      channelLabel: "復旧用メール1",
    }),
    sendRecoveryEmail({
      to: secondaryEmail,
      code: secondaryCode,
      channelLabel: "復旧用メール2",
    }),
  ]);

  primaryCode = "";
  secondaryCode = "";

  if (results.some((result) => result.status === "rejected")) {
    return json(
      { error: "復旧メールを2通とも送信できませんでした。もう一度お試しください。" },
      502,
    );
  }

  return json({
    challengeId,
    expiresAt,
    sent: true,
  });
});
