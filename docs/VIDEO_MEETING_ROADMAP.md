# SKO Video Meeting Roadmap

## Timing

Future expansion after the current TestFlight/stability work. The current release must not be delayed by video calling.

## Goal

Add video meetings inside SKO chat without replacing the existing chat model.

Supported meeting scopes:

- 1-to-1 chat video meeting.
- Existing SKO group chat video meeting.
- Site/project-specific video meeting.
- Company/team video meeting where permissions allow.

## Architecture requirements

- Reuse existing SKO user, company, group and site identifiers.
- A meeting belongs to a conversation/scope instead of creating a separate people directory.
- Invitation, ringing, join/leave and ended states must work for both individual and group calls.
- Participants must be authorized members of the target conversation/site/company.
- Country and language packs must remain independent from the media transport provider.
- Media transport/provider must sit behind an interface so the provider can be replaced later without rebuilding SKO chat.
- Do not store raw camera/microphone media by default.
- Recording must be a separate explicit feature with visible participant consent and country-specific legal handling.
- Camera/microphone permissions are requested only when needed.
- Meeting metadata should support master-level aggregate metrics without exposing call content.

## Future UX

Chat header:
- Video call button.
- For a group/site: start meeting and invite authorized members.
- For 1-to-1: call the other member directly.

During meeting:
- Mute/unmute.
- Camera on/off.
- Speaker/audio route.
- Participant list.
- Leave/end meeting.
- Network/reconnect state.

## Implementation phases

1. Provider-neutral meeting domain/API contract.
2. 1-to-1 prototype.
3. Group meeting.
4. Site/project meeting.
5. Notifications/incoming-call UX.
6. Security, abuse controls and permission audit.
7. International/legal/recording policy if recording is introduced.
8. Real-device and network-condition testing.
