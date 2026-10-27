// Pure projection only. A caller must authenticate the collector and resolve
// recipient from a trusted, current Master registration before calling.
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const HASH=/^[0-9a-f]{64}$/;
const keys=['collector_id','correlation_key','event_id','event_kind','generation','key_epoch','occurred_at'];
export function projectObservationNotice({observation, trustedRecipient, registeredCollector}) {
  if (!observation || Array.isArray(observation) || typeof observation !== 'object' ||
      Object.keys(observation).sort().join(',') !== keys.join(',') ||
      !UUID.test(observation.event_id ?? '') || !UUID.test(observation.collector_id ?? '') ||
      !UUID.test(trustedRecipient ?? '') || observation.collector_id !== registeredCollector ||
      !HASH.test(observation.correlation_key ?? '') ||
      !Number.isSafeInteger(observation.generation) || observation.generation < 1 || observation.generation > 1000000 ||
      !['current_lure_touched','retired_lure_touched'].includes(observation.event_kind) ||
      typeof observation.occurred_at !== 'string' ||
      !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(observation.occurred_at)) throw Error('Untrusted observation');
  const at=Date.parse(observation.occurred_at);
  if (!Number.isFinite(at) || new Date(at).toISOString() !== observation.occurred_at ||
      observation.key_epoch !== observation.occurred_at.slice(0,10)) throw Error('Untrusted observation');
  return Object.freeze({recipient_id:trustedRecipient,event_id:observation.event_id,
    notice_type:'decoy_contact',occurred_at:observation.occurred_at,
    event_kind:observation.event_kind,generation:observation.generation,
    scope:'decoy_generation_only',state:'observed',
    title:'監視対象へのアクセスを検知',
    message:observation.event_kind==='current_lure_touched'
      ? '現在の監視対象へのアクセスを記録しました。内容を確認してください。'
      : '以前の監視対象へのアクセスを記録しました。内容を確認してください。'});
}
