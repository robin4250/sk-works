import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

type LineWebhookEvent = {
  type?: string;
  timestamp?: number;
  source?: {
    type?: string;
    groupId?: string;
    userId?: string;
  };
  message?: {
    id?: string;
    type?: string;
    text?: string;
  };
};

type LineWebhookBody = {
  destination?: string;
  events?: LineWebhookEvent[];
};

type LineGroupMemberProfile = {
  displayName?: string;
};

const encoder = new TextEncoder();

function decodeBase64(value: string): Uint8Array {
  const decoded = atob(value);
  return Uint8Array.from(decoded, (char) => char.charCodeAt(0));
}

async function verifyLineSignature(
  rawBody: string,
  signature: string,
  channelSecret: string,
): Promise<boolean> {
  const key = await crypto.subtle.importKey(
    'raw',
    encoder.encode(channelSecret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['verify'],
  );

  return crypto.subtle.verify(
    'HMAC',
    key,
    decodeBase64(signature),
    encoder.encode(rawBody),
  );
}

async function loadLineGroupMemberDisplayName(
  groupId: string,
  userId: string,
  channelAccessToken: string,
): Promise<string | null> {
  try {
    const response = await fetch(
      `https://api.line.me/v2/bot/group/${encodeURIComponent(groupId)}/member/${encodeURIComponent(userId)}`,
      {
        headers: {
          Authorization: `Bearer ${channelAccessToken}`,
        },
      },
    );

    if (!response.ok) {
      console.warn(
        'Could not enrich LINE sender profile',
        response.status,
        groupId,
        userId,
      );
      return null;
    }

    const profile = (await response.json()) as LineGroupMemberProfile;
    finalDisplayName: {
      const displayName = profile.displayName?.trim();
      if (!displayName) return null;
      return displayName.slice(0, 200);
    }
  } catch (error) {
    console.warn('Could not enrich LINE sender profile', error);
    return null;
  }
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response('Method Not Allowed', { status: 405 });
  }

  const channelSecret = Deno.env.get('LINE_CHANNEL_SECRET');
  const channelAccessToken = Deno.env.get('LINE_CHANNEL_ACCESS_TOKEN');
  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

  if (!channelSecret || !supabaseUrl || !serviceRoleKey) {
    console.error('LINE webhook environment variables are incomplete.');
    return new Response('Server configuration error', { status: 500 });
  }

  const rawBody = await req.text();
  const signature = req.headers.get('x-line-signature') ?? '';

  if (!signature) {
    return new Response('Missing LINE signature', { status: 401 });
  }

  let signatureIsValid = false;
  try {
    signatureIsValid = await verifyLineSignature(rawBody, signature, channelSecret);
  } catch (error) {
    console.error('Could not verify LINE signature', error);
  }

  if (!signatureIsValid) {
    return new Response('Invalid LINE signature', { status: 401 });
  }

  let payload: LineWebhookBody;
  try {
    payload = JSON.parse(rawBody) as LineWebhookBody;
  } catch (_) {
    return new Response('Invalid JSON', { status: 400 });
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  for (const event of payload.events ?? []) {
    if (
      event.type !== 'message' ||
      event.source?.type !== 'group' ||
      event.message?.type !== 'text'
    ) {
      continue;
    }

    const lineGroupId = event.source.groupId;
    const externalMessageId = event.message.id;
    const text = event.message.text?.trim();

    if (!lineGroupId || !externalMessageId || !text) {
      continue;
    }

    const { data: binding, error: bindingError } = await supabase
      .from('line_group_bindings')
      .select('company_id, communication_group_id, is_enabled')
      .eq('line_group_id', lineGroupId)
      .eq('is_enabled', true)
      .maybeSingle();

    if (bindingError) {
      console.error('Could not load LINE group binding', bindingError);
      continue;
    }

    if (!binding) {
      // Deliberately ignore unbound groups. This lets the bot be added safely
      // before an administrator explicitly connects the LINE group to SKO.
      console.info('Ignoring message from unbound LINE group', lineGroupId);
      continue;
    }

    const externalSenderId = event.source.userId ?? null;
    const externalSenderName =
      externalSenderId && channelAccessToken
        ? await loadLineGroupMemberDisplayName(
            lineGroupId,
            externalSenderId,
            channelAccessToken,
          )
        : null;
    const createdAt = event.timestamp
      ? new Date(event.timestamp).toISOString()
      : new Date().toISOString();

    const { error: insertError } = await supabase
      .from('communication_messages')
      .insert({
        company_id: binding.company_id,
        group_id: binding.communication_group_id,
        body: text.slice(0, 5000),
        origin: 'line',
        external_message_id: externalMessageId,
        external_sender_id: externalSenderId,
        external_sender_name: externalSenderName,
        created_by: null,
        created_at: createdAt,
      });

    if (insertError && insertError.code !== '23505') {
      console.error('Could not store LINE message', insertError);
    }
  }

  return new Response('OK', { status: 200 });
});
