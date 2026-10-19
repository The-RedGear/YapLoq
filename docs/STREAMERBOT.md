# Streamer.bot recipes

## Actions workspace

**Actions** is the default Streamer.Bot tab. Select an automation on the left;
its event triggers and ordered sub-actions are on the right. Add as many Run action
and Delay steps as needed, reorder them with the up/down controls or context menus,
and choose Stop or Continue if a step fails. Conditions narrow a trigger by alias,
source, viewer or other available message fields.

In a Run action step, **Load actions** reads the connected instance's HTTP
GetActions endpoint. Search by name, select an action, or enter an exact name/ID.
Arguments are an optional JSON object; string values can include placeholders such
as {ttsText}, {ttsAlias}, {ttsUser}, {ttsId} and {ttsSource}.

**Save actions** validates the complete list and creates a settings backup before
applying it. Existing fixed playback hooks appear as migrated queue-session actions;
their original behavior remains active until the first save. After migration,
those hooks are edited here rather than in the old fixed slots.

Queue-session triggers deliberately differ from per-message events: “Queue: all
speech finished” waits until every tracked item is done; “Message finished” fires
for each recording. Existing before-playback timing remains in Connection.

Runs currently queue in saved order. Delay steps are interruptible on shutdown.
HTTP DoAction confirms dispatch, not completion of remote sub-actions. For strict
remote execution ordering, configure the target actions in a blocking queue in
Streamer.Bot. Failed steps appear in YapLoq's event inspector and logs.

Official API: [GetActions](https://docs.streamer.bot/api/http/requests/get-actions)
and [DoAction](https://docs.streamer.bot/api/http/requests/do-action).

## Connection diagnostics

In **Streamer.Bot → Connection**, the listener status shows the active UDP port
or a startup error such as a port already in use. Counts show UDP requests received,
accepted and rejected since launch, with the latest rejection reason. Acceptance
does not mean playback has finished: check Queue for generation/playback results.

**Test listener** sends a local probe without speaking or changing request counts.
For a full test from Streamer.Bot, run the imported Speak action with a Test trigger
and watch these counts and Queue. Save and restart after changing listener settings.

## Speech actions

The YapLoq Streamer.bot page copies UDP payloads for speech and queue controls.
Use UDP Broadcast with port 6670, unless you changed it in YapLoq.

Alternatively, choose the Speak alias and select **Export actions (.sb)**. Import
that file using Streamer.bot's Import dialog and review its ten actions before
applying it. It does not create triggers or run an action automatically. Export
IDs are stable, so later imports update the same YapLoq actions. Keep your own
customizations under different action names or disable overwriting in the import
preview. The generator targets the official v10 export envelope (0.2.4 schema).
Live import behavior across Streamer.bot versions still needs verification.

```text
VSPEAK
Windows voice
%message%
%displayName%
%userName%
```

For a random voice among aliases marked **ON** in the Voices tab, use `random` (or `*`) on line 2:

```text
VSPEAK
random
%message%
%displayName%
%userName%
```

For a custom pool from **Rules → Voice playlists**, use `playlist:Name`:

```text
VSPEAK
playlist:Halo
%message%
%displayName%
%userName%
```

`group:Halo` still picks randomly within that alias **Group** field (ON voices only). Export actions (.sb) can select **Random (enabled voices)** or **Playlist: Name**.

Line 1 is the command, line 2 is the voice alias (or `random` / `group:Name`), line 3 is the spoken text.
Optional line 4 is the viewer display name (`%displayName%` or `%user%` when it is a
plain name), line 5 is the Twitch login (`%userName%`), and line 6 can be a role.
Do not put Streamer.bot's `%user%` object JSON on the identity lines — in current
Streamer.bot builds `%user%` often expands to a whole `{"badges":...,"login":...}`
blob. Use `%displayName%` + `%userName%` instead. Automatic voice rules match either
identity case-insensitively. A single optional identity line is also accepted and
matched as both display and login. If a JSON user object still arrives, YapLoq
extracts `name` / `login` automatically.

```text
VCONTROL
pause
```

Control tokens: `pause`, `pauseaftercurrent`, `resume`, `skip`, `clear`, `clearall`,
`remove`, `moveup`, `movedown`. The last three require the speech ID on line three.
`clear` keeps current speech; `clearall` stops current speech too.

HTTP uses port 7582 by default:

| POST endpoint | JSON body |
| --- | --- |
| `/speak` | `{"voice":"Windows voice","message":"Hello","source":"Twitch","user":"viewer","role":"subscriber","event":"reward","priority":10}` |
| `/pause` | `{}` |
| `/pause-after-current` | `{}` |
| `/resume` | `{}` |
| `/skip` | `{}` |
| `/clear` | `{}` |
| `/clear-all` | `{}` |
| `/api/queue/remove` | `{"speechId":"id"}` |
| `/api/queue/move` | `{"speechId":"id","direction":"up"}` |
| `/api/profiles/load` | `{"profile":"Quiet"}` |

WebSocket uses port 7581. Send a request with a unique ID:

```json
{"id":"queue-pause","request":"Pause"}
```

```json
{"id":"scene-profile","request":"LoadProfile","profile":"Quiet"}
```

Subscribe to events:

```json
{"id":"events","request":"Subscribe","events":{"texttospeech":["received","generating","engineprocessed","playing","finished","cancelled","error"]}}
```

The lifecycle follows received → generating → engineprocessed → textqueued →
playing → finished, cancelled or error. Cached replay and output tests can skip
generation. Raw events describe each job. Configured Queued and Playing actions
announce a queue session once; Finished waits for every registered job to end.

The pre-playback delay starts after the Queued action's HTTP request completes.
It applies when that action was actually dispatched, rather than inserting the
same delay between every item. Streamer.bot may run an action asynchronously;
HTTP acknowledgement does not prove all of its sub-actions have finished.

Lifecycle arguments include `ttsState`, `ttsId`, `ttsText`, `ttsAlias`, `ttsVoice`,
`ttsSource`, `ttsUser` and `ttsDuration`. The test buttons exercise configured
actions without adding fake items to the live queue's lifecycle state.

Additional per-message hooks cover Received, Generating, Generated, Failed and
Cancelled/Skipped. Individual failure and cancellation hooks use `itemError` and
`itemCancelled` as ttsState, separately from the queue-session Finished hook.

To change profiles with an OBS scene, attach an HTTP or WebSocket LoadProfile
request to the scene action in Streamer.bot. To animate an avatar, use Queued,
Playing and Finished actions; use Queue added for a pulse when another message
joins an active session.

## Persistent viewer voices

Manage assignments under **Voices > Assignments**. The Viewers section assigns an enabled alias, playlist,
or random enabled voice; Reset removes the preference but retains the viewer.
Assignments live in `data/viewers.json` (`data-preview/viewers.json` for the
development preview). Writes are atomic and keep a previous `.json.bak` copy.
Settings-only backup/restore currently does not include this separate file.

Stable identities require both `platform` and `userId`. IDs are case-sensitive;
display names and logins are presentation/moderation fields, not assignment keys.
New stable identities are remembered from speech requests, and renamed viewers
retain their preferences. Old name-only VSPEAK packets still work with existing
username/role rules, but cannot safely create stable viewer assignments.

Trusted local integrations can POST `/api/viewers/set`:

```json
{"platform":"twitch","userId":"12345","displayName":"Example","voice":"playlist:Characters"}
```

Use `"voice":""` to reset. GET `/api/viewers` returns viewers, assignment origin,
availability warnings and available selectors. WebSocket requests use
`SetViewerVoice`, `GetViewerVoice` and `GetViewers` with the same fields plus the
normal request `id`. JSON UDP can use `"command":"SetViewerVoice"`.

To use a saved preference, omit the voice from a speech request:

```json
{"platform":"twitch","userId":"12345","user":"Example","message":"Hello!"}
```

Voice precedence is explicit request → saved viewer preference → first matching
conditional voice rule → legacy name/role fallback → configured default → first
enabled voice. Missing/disabled selectors are retained for repair and fall
through to the next fallback. An invalid explicit voice still reports an error;
it is never silently replaced. Waiting/playing jobs keep their resolved voice.

The Rules section contains the existing conditional and name/role editors;
old Routing links open this section. Priority is independent: the first matching
rule that specifies priority applies even when the voice is explicit or assigned
to a viewer. Choose **Keep chosen voice (priority only)** to create a priority-only
rule. A voice-only rule without a priority field does not block a later priority
rule. Rule saving does not apply unrelated Queue filter/limit edits.

The Default voice section saves an alias, playlist or random enabled selector in
`data/settings.json` as `assignment_default_voice`. Automatic uses the first
enabled voice. This setting is included in voice presets/profiles.

Streamer.Bot action export offers **Use assignments**, which leaves the VSPEAK
alias line blank. Existing explicit exports keep their selected voice and now
take precedence over automatic rules. Re-export using Use assignments if an old
action should follow the automatic assignment system instead.

Dashboard and Queue message menus offer **Set viewer default to this voice**
when the message contains stable identity. Public voice restrictions and chat
`!voice` command permission checks are not implemented yet; do not forward
unvalidated viewer chat directly into the trusted assignment API.
# Viewer voice commands

## Multiple voices in one message

### Change a waiting message's voice

In Queue, select an entry still marked Queued and choose Change voice (also available on right-click). The icon/color-aware picker changes that entry only, without moving it, changing its timestamp/text, editing saved aliases, or interrupting playback. Each multi-voice segment can be changed independently. Generating, prepared, replayed, currently playing and completed entries cannot be changed. If generation begins while the picker is open, Apply rejects the edit without modifying the message. Plain-text and SSML modes must match.

Trusted integrations can call `ChangeSpeechVoice` with `speechId` and `voice`, or POST `/api/queue/voice`. Successful edits emit `texttospeech.voicechanged` (Queued voice changed in the Actions trigger menu) with the same speech ID and `previousAlias`. This does not generate a new received/queue-added event or reset cooldowns.

New exports use `YAPLOQ2` for identity-first speech and `YAPLOQVOICE` for viewer commands. Old `VSPEAK2` and `VVOICE` packets remain supported. `YAPLOQ` is a drop-in synonym for the original `VSPEAK` layout (alias, message, display name, username); changing that marker alone does not add viewer identity or fix alias-name errors. Use the new exported format for unambiguous multiline speech. Voice tags accept an exact name or a unique word-prefix, so `[Spongebob]` can select `Spongebob Squarepants`; ambiguous prefixes are rejected. Dashboard and Queue display individual entries newest-first, including multi-voice segments. Playback remains in input order. Status, replays and late history updates never promote entries; explicit Move up/down actions are the only ordering override.

Use `[Plankton] Hello! [Spongebob] Hi!` in Dashboard or a speech action's text. Each nonempty segment becomes one queue item with its own voice icon/color and status. Tags are case-insensitive; use the complete alias name in Dashboard and the public voice name for viewer inputs. Text before the first tag uses the selected voice or Assignments result. Repeated tags are allowed; empty segments are skipped. Use `\[` for a literal opening bracket. Unknown/unavailable tags reject the whole input rather than speaking the tag.

All segments are validated before any are queued. Character limits apply to their combined spoken text, each segment counts toward queue/user limits, and the request consumes one cooldown. Up to 20 tags are supported. Multi-voice inputs are plain text, not SSML. Normal priority and manual queue controls still apply; generation-ahead does not reorder segments. Identified viewers can only tag eligible public voices. Dashboard and legacy owner-controlled actions without stable viewer identity can use private aliases, matching existing explicit-alias behavior. For viewer-facing permissions, use the new templates with platform/user ID, not the legacy VSPEAK format. An explicit source field is integration metadata, not an authorization boundary; keep the local APIs trusted.

The Speak response retains `speechId` for the first segment and adds `speechIds` and `segments` for the complete input. Existing speech lifecycle events fire for each segment independently.

In Voices > Assignments > Viewer commands, enable commands and save. In each voice editor, expand Viewer access to make it public, optionally give it a chat-facing name, and choose its audience. Existing voices are private by default.

Choose Twitch, YouTube, Kick, or Event platform in that page and copy the templates. Import them in Streamer.Bot. They create two actions, not commands or triggers:

- **Viewer voice command**: create a Starts With `!voice` command in Streamer.Bot and attach its Command Triggered trigger to this action.
- **Speak using viewer assignment**: attach a separate Starts With speech command (for example `!say`). This forwards `%rawInput%` as speech and leaves the alias blank so Assignments can choose it. Do not attach the `!voice` trigger to this speech action.

Enable YapLoq's UDP listener first. Both templates forward platform, stable user ID, username, role, subscription, VIP and moderator flags from the event; never substitute roles or IDs supplied in chat text. Platform-specific templates avoid relying on `%commandSource%`; Event platform uses that variable. Unsupported or unresolved audience flags do not grant extra access. Importing does not run actions or replace the regular Speak action. Template IDs are stable per platform for repeat imports.

Commands: `!voice` or `!voice list`, `!voice name`, `!voice random`, and `!voice reset`. Random saves one eligible voice until changed. Reset returns to assignment rules/defaults. Private or restricted voices cannot be chosen, and access is checked again on each speech request. Owner-created assignments may still use private voices.

Re-export the Speak action with **Use assignments** to apply viewer choices. New Speak exports include stable identity and audience fields using VSPEAK2; old VSPEAK actions remain supported but cannot identify viewer preferences without those fields. For a non-command chat trigger, supply its actual platform in place of `%commandSource%` if that event does not provide the variable. Explicit voice exports intentionally override assignments.

### Result actions and chat replies

Use **Add trigger** (or right-click the trigger list) to browse Speech, Queue, Playback, Viewers, Integrations, and Queue sessions. Hover a category to open its events, then click an event to add it. Existing triggers keep their saved source/event IDs. Adding the same trigger twice does not duplicate it.

In Streamer.Bot > Actions inside YapLoq, create an action and choose one of these triggers:

- Viewer voice command received: a recognized `!voice` request arrived, before validation.
- Viewer voice set successfully: a permitted choice was saved, including random selection.
- Viewer voice reset successfully: the saved preference was cleared.
- Viewer requested available voices: the permitted public voice list is ready.
- Viewer voice command failed: commands are disabled, identity is missing, the choice is unavailable/restricted, or saving failed. No assignment is changed.

Add a Run Streamer.Bot action sub-action, choose your reply action, and map arguments such as:

```json
{"message":"{ttsReply}","platform":"{ttsPlatform}","viewerId":"{ttsUserId}","user":"{ttsUser}"}
```

Your Streamer.Bot reply action can use `%message%` and route to the matching platform. Set conditions on `platform` when using separate Twitch, YouTube or Kick reply actions. The same YapLoq action can handle several result triggers, or each can run different actions and delays. A received trigger is not a success notification.

Viewer event arguments also include `ttsPublicVoice`, `ttsAlias` (canonical internal name on success), `ttsReason`, `ttsError`, `ttsState` and `ttsId` (request correlation ID, not a speech ID). Failure reasons are `disabled`, `identity`, `unavailable`, or `storage`. Failure events never echo the raw command or a requested private voice name. Use `ttsPublicVoice`, not `ttsAlias`, in public chat replies.

The UDP templates do not send chat replies automatically; configured result actions do that. Trusted HTTP/WebSocket integrations can use `ViewerVoiceCommand` (HTTP POST `/api/viewers/command`) and its `reply` result instead. Avoid using both reply paths for the same request. Audience metadata must come from the integration's event. Do not expose these trusted local APIs to untrusted clients. Platforms without recognized audience metadata receive only Everyone voices.
