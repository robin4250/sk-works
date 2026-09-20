import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const encoder = new TextEncoder();

function constantTimeEqual(a: string, b: string) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

async function hmacSha256Base64(secret: string, body: string) {
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("HMAC", key, encoder.encode(body));
  const bytes = new Uint8Array(signature);
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary);
}

async function lineGroupMemberDisplayName(groupId: string, userId: string) {
  const token = Deno.env.get("LINE_CHANNEL_ACCESS_TOKEN");
  if (!token) return null;

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 1500);
  try {
    const response = await fetch(
      `https://api.line.me/v2/bot/group/${encodeURIComponent(groupId)}/member/${encodeURIComponent(userId)}`,
      {
        method: "GET",
        headers: { Authorization: `Bearer ${token}` },
        signal: controller.signal,
      },
    );
    if (!response.ok) return null;

    const profile = await response.json();
    const displayName = typeof profile?.displayName === "string"
      ? profile.displayName.trim()
      : "";
    return displayName || null;
  } catch {
    return null;
  } finally {
    clearTimeout(timeout);
  }
}

async function rest(path: string, init: RequestInit = {}) {
  const url = Deno.env.get("SUPABASE_URL");
  const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceRole) throw new Error("Supabase service configuration missing");
  return fetch(`${url}/rest/v1/${path}`, {
    ...init,
    headers: {
      apikey: serviceRole,
      Authorization: `Bearer ${serviceRole}`,
      "Content-Type": "application/json",
      Prefer: "return=minimal",
      ...(init.headers ?? {}),
    },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return new Response("Method Not Allowed", { status: 405 });

  const secret = Deno.env.get("LINE_CHANNEL_SECRET");
  if (!secret) return new Response("Server configuration missing", { status: 500 });

  const rawBody = await req.text();
  const receivedSignature = req.headers.get("x-line-signature") ?? "";
  const expectedSignature = await hmacSha256Base64(secret, rawBody);
  if (!receivedSignature || !constantTimeEqual(receivedSignature, expectedSignature)) {
    return new Response("Invalid signature", { status: 401 });
  }

  let payload: any;
  try {
    payload = JSON.parse(rawBody);
  } catch {
    return new Response("Invalid JSON", { status: 400 });
  }

  const events = Array.isArray(payload?.events) ? payload.events : [];

  for (const event of events) {
    const source = event?.source ?? {};
    const groupId = source?.groupId ?? null;
    const roomId = source?.roomId ?? null;
    const userId = source?.userId ?? null;
    const webhookEventId = event?.webhookEventId ?? null;
    const messageType = event?.message?.type ?? null;
    const messageText = messageType === "text" ? event?.message?.text ?? null : null;

    const rawInsert = await rest("line_webhook_events?on_conflict=webhook_event_id", {
      method: "POST",
      headers: { Prefer: "resolution=ignore-duplicates,return=minimal" },
      body: JSON.stringify({
        webhook_event_id: webhookEventId,
        group_id: groupId,
        room_id: roomId,
        user_id: userId,
        event_type: event?.type ?? null,
        message_type: messageType,
        message_text: messageText,
        raw_event: event,
      }),
    });
    if (!rawInsert.ok && rawInsert.status !== 409) {
      console.error("line_webhook_events insert failed", rawInsert.status, await rawInsert.text());
    }

    if (!groupId || event?.type !== "message" || messageType !== "text" || !messageText) continue;

    const claimMatch = messageText.match(/^\s*SKO連携[\s　]+([A-F0-9]{8})\s*$/i);
    if (claimMatch) {
      const claimResp = await rest("rpc/complete_line_group_claim_for_line", {
        method: "POST",
        body: JSON.stringify({
          p_claim_code: claimMatch[1].toUpperCase(),
          p_line_group_id: groupId,
        }),
      });
      if (!claimResp.ok) {
        console.error("LINE binding claim failed", claimResp.status, await claimResp.text());
      }
      continue;
    }

    const bindingResp = await rest(
      `line_group_bindings?line_group_id=eq.${encodeURIComponent(groupId)}&status=eq.active&select=company_id,communication_group_id&limit=1`,
      { method: "GET", headers: { Prefer: "" } },
    );
    if (!bindingResp.ok) {
      console.error("binding lookup failed", bindingResp.status, await bindingResp.text());
      continue;
    }
    const bindings = await bindingResp.json();
    if (!Array.isArray(bindings) || bindings.length === 0) continue;

    const binding = bindings[0];
    if (!binding.company_id || !binding.communication_group_id) continue;

    const sentAt = typeof event?.timestamp === "number"
      ? new Date(event.timestamp).toISOString()
      : new Date().toISOString();

    const senderDisplayName = userId
      ? await lineGroupMemberDisplayName(groupId, userId)
      : null;

    const chatResp = await rest("chat_messages?on_conflict=external_event_id", {
      method: "POST",
      headers: { Prefer: "resolution=ignore-duplicates,return=minimal" },
      body: JSON.stringify({
        company_id: binding.company_id,
        communication_group_id: binding.communication_group_id,
        sender_display_name: senderDisplayName ?? (userId ? `LINE:${userId}` : "LINE"),
        origin: "line",
        body: messageText,
        external_event_id: webhookEventId,
        external_message_id: event?.message?.id ?? null,
        sent_at: sentAt,
      }),
    });
    if (!chatResp.ok && chatResp.status !== 409) {
      console.error("chat message insert failed", chatResp.status, await chatResp.text());
    }
  }

  return new Response("OK", { status: 200 });
});
